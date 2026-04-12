# Round Recovery Hardening — Design

**Date:** 2026-04-11
**Branch:** WeaponsBranch
**Source:** Codex adversarial review flagged four hard-failure paths in the round flow. This spec makes each one fail-closed instead of silently degrading.

## Goals

1. Reject invalid teleport metadata at the server boundary and kick the affected player.
2. Default missing/empty loadouts from a single config constant without mutating the constant.
3. Bound character loading at round start. Kick players who fail to load within the timeout; the existing `PlayerRemoving` pipeline handles the disconnect bookkeeping automatically.
4. Kick players when the post-match lobby teleport retries are exhausted so nobody is stranded in a dead server.
5. Loud, complete weapon validation at server boot. If anything is wrong, abort any round that tries to start.

## Non-Goals

- No changes to the knife/gun client-authoritative prediction pipeline.
- No changes to `PlayerState`, `TeamState`, `WinConditionEvaluator`, or the state machine.
- No retry-count tuning. Existing `RETRY_COUNT = 3` with base-1 exponent-2 backoff stays.
- No new UI. No `Instance.new` for anything UI-adjacent. Per CLAUDE.md, the single `BindableEvent` used for positioning coordination is pre-built and injected — not constructed in code.

## Verified Issues (from Codex review)

All four findings verified against current code on `WeaponsBranch`.

1. **`executor.server.lua:30-46`** — invalid teleport data → `warn + return`. `CharacterAutoLoads = false` is already set globally, so the player stays in the server with no character. Fix: kick.
2. **`RoundOrchestrator.lua:38-80`** — `loadAndPositionPlayers` increments `remaining`, blocks on `CharacterAdded:Wait()`, decrements only on success. If load never resolves or player leaves mid-spawn, the counter never hits zero, `_positioningPlayers` stays true, win checks are suppressed, round timer never arms. Fix: bounded wait + guaranteed decrement + kick-on-timeout.
3. **`RoundOrchestrator.lua:245-248`** — `teleportPlayersWithRetry` is only warned about after exhaustion. Players stay stuck in the finished match server. Fix: kick all players on exhaustion.
4. **`WeaponDistributor/executor.server.lua:13-46`** — 5 independent `warn + return` exit paths that silently disable distribution while the round proceeds. Fix: collect-and-report validation + abort-on-startup-failure via a shared ready flag.

## Config changes

**`src/Shared/Round/Configs.lua`** — additions and one edit:

```lua
CHARACTER_LOAD_TIMEOUT = 7,  --// was 10

DEFAULT_LOADOUT = {
    knifeName = "Default",  --// placeholder, user will edit
    gunName = "Default",
},

KICK_REASONS = {
    InvalidTeleportData = "Invalid match data. Returning to lobby.",
    CharacterLoadTimeout = "Character failed to load in time.",
    TeleportOutFailed = "Unable to return to lobby. Please rejoin.",
},
```

`RETRY_COUNT`, `EXPONENTIAL_BACKOFF_BASE`, `EXPONENTIAL_BACKOFF_EXPONENT` unchanged (already `3`, `1`, `2`). `N` in "kick after N failed lobby teleports" = `RETRY_COUNT`.

## 1. Teleport-data validation and defaulting

**Problem.** Current validator returns `(ok, err)` and the executor silently drops invalid-data players into a no-character limbo.

**Change — `TeleportDataValidator.validate`** now returns `(ok: boolean, err: string?, sanitized: table?)`. Semantics:

- Missing or wrong-type `teamOnePlayers`, `teamTwoPlayers`, `mapName`, `queueType`, or `timestamp` → `ok = false`, `sanitized = nil`.
- Loadouts are **non-authoritative**. The validator fills every missing field from `Configs.DEFAULT_LOADOUT`. No half-validate behavior — post-sanitization, every player has a fully-populated loadout.
- Rules:
    - If `sanitized.loadouts` is missing or non-table → initialize to `{}`.
    - For every player in both team rosters, if `sanitized.loadouts[tostring(userId)]` is missing → create from `cloneDefaultLoadout()`.
    - If an entry exists but `knifeName` is nil → fill from `DEFAULT_LOADOUT.knifeName`.
    - If an entry exists but `gunName` is nil → fill from `DEFAULT_LOADOUT.gunName`.
- Always clone so the config constant can never be mutated:

```lua
local function cloneDefaultLoadout()
    return {
        knifeName = Configs.DEFAULT_LOADOUT.knifeName,
        gunName = Configs.DEFAULT_LOADOUT.gunName,
    }
end

local function fillLoadouts(sanitized)
    if type(sanitized.loadouts) ~= "table" then
        sanitized.loadouts = {}
    end
    local function fillFor(entry)
        local key = tostring(entry.UserId)
        local loadout = sanitized.loadouts[key]
        if not loadout then
            sanitized.loadouts[key] = cloneDefaultLoadout()
            return
        end
        if loadout.knifeName == nil then loadout.knifeName = Configs.DEFAULT_LOADOUT.knifeName end
        if loadout.gunName == nil then loadout.gunName = Configs.DEFAULT_LOADOUT.gunName end
    end
    for _, entry in sanitized.teamOnePlayers do fillFor(entry) end
    for _, entry in sanitized.teamTwoPlayers do fillFor(entry) end
end
```

**Change — `src/Server/RoundService/executor.server.lua`** real-data branch:

```lua
local ok, err, sanitized = TeleportDataValidator.validate(teleportData)
if not ok then
    warn(`[Round] Invalid teleport data for {player.Name}: {err}`)
    player:Kick(Configs.KICK_REASONS.InvalidTeleportData)
    return
end
teleportData = sanitized
```

`TEST_MODE` branch is unaffected — template data already has valid structure.

## 2. Bounded character loading + injected BindableEvent

**Problem.** Unbounded `CharacterAdded:Wait()` with only-on-success decrement.

**Design constraint.** Per CLAUDE.md, no `Instance.new` for UI-adjacent things. The positioning-done signal is a pre-built `BindableEvent` looked up at a **placeholder path**: `ServerStorage.RoundEvents.PositioningDone`. The user will relocate it post-approval.

**Change — `src/Server/RoundService/executor.server.lua`** startup:

```lua
local ServerStorage = game:GetService("ServerStorage")
--// PLACEHOLDER PATH — relocate post-approval
local positioningDoneEvent =
    ServerStorage:WaitForChild("RoundEvents"):WaitForChild("PositioningDone")
```

Then when creating the round:

```lua
roundSystem = RoundService.new(teleportData, positioningDoneEvent)
```

**Change — `src/Server/RoundService/init.lua`** — `RoundSystem.new(metadata, positioningDoneEvent)` stores `self._positioningDoneEvent = positioningDoneEvent`.

**Change — `src/Server/RoundService/RoundOrchestrator.lua`** — replace `loadAndPositionPlayers`:

```lua
local function loadAndPositionPlayers(system)
    local spawnGroups = getSpawnAssignment(system)
    local remaining = 0
    local doneEvent = system._positioningDoneEvent

    for teamNum, spawns in spawnGroups do
        local players = system._teamPlayers[teamNum]
        if #spawns == 0 then
            warn(`[Round] No spawn parts found for team {teamNum}`)
            continue
        end
        for i, player in players do
            if not system._playerStates[player] then
                warn(`[Round] {player.Name} skipped — no playerState`)
                continue
            end
            remaining += 1
            local spawnPart = spawns[((i - 1) % #spawns) + 1]

            task.spawn(function()
                local deadline = os.clock() + Configs.CHARACTER_LOAD_TIMEOUT

                pcall(function()
                    if not player.Character
                        or not player.Character:FindFirstChild("Humanoid")
                        or player.Character.Humanoid.Health <= 0
                    then
                        player:LoadCharacter()
                    end
                end)

                --// Wait for the character model itself (may already exist).
                local character = player.Character
                if not character and player.Parent then
                    local result
                    local conn = player.CharacterAdded:Connect(function(c)
                        result = c
                    end)
                    while not result and os.clock() < deadline and player.Parent do
                        task.wait()
                    end
                    conn:Disconnect()
                    character = result
                end

                --// Wait for HumanoidRootPart to replicate, bounded by the
                --// remaining deadline. This is the real "character is usable"
                --// signal — CharacterAdded can fire before HRP is available.
                local rootPart
                if character and player.Parent then
                    local remainingTime = deadline - os.clock()
                    if remainingTime > 0 then
                        rootPart = character:WaitForChild("HumanoidRootPart", remainingTime)
                    end
                end

                if rootPart then
                    rootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
                    print(`[Round] {player.Name} → Team {teamNum} → {spawnPart.Name}`)
                else
                    warn(`[Round] Character load timed out for {player.Name} — kicking`)
                    if player.Parent then
                        player:Kick(Configs.KICK_REASONS.CharacterLoadTimeout)
                    end
                end

                remaining -= 1
                if remaining == 0 then
                    doneEvent:Fire()
                end
            end)
        end
    end

    if remaining > 0 then
        doneEvent.Event:Wait()
    end
end
```

**Invariants.**

- `remaining -= 1` runs on every exit path: success, timeout, `LoadCharacter` error, player leaves.
- Lua is cooperative — no races on the `remaining` counter.
- The skip-wait-if-zero check prevents a deadlock when all spawned tasks run to completion before the main thread reaches `doneEvent.Event:Wait()`.
- `player:Kick` triggers `Players.PlayerRemoving`, which calls `RoundSystem:UnregisterPlayer`, which sets `Disconnected` status, captures stats into `_disconnectedStats`, fires `PlayerStatusChanged`, broadcasts, and calls `_checkWinCondition`. The last step is suppressed because `_positioningPlayers` is still `true` — win condition is re-evaluated after positioning finishes.

## 3. Teleport-out retry exhaustion

**Problem.** `teleportPlayersWithRetry` warns after exhausting 3 attempts. Players stay trapped.

**Change — `src/Server/RoundService/TeleportUtility.lua`** — in the exhaustion branch:

```lua
else
    warn(`[TeleportUtility] All {Configs.RETRY_COUNT} attempts exhausted: {err}`)
    for _, player in players do
        if player.Parent then
            player:Kick(Configs.KICK_REASONS.TeleportOutFailed)
        end
    end
    return false, err
end
```

Caller in `RoundOrchestrator.enterTeleportingOut` is unchanged — it already logs `not ok`, and the kick has already happened by then.

## 4. Weapon system readiness gate

**Problem.** Weapon distributor has five independent early-return paths (`warn + return`) that leave `_roundActive` listener set up but no templates registered. Round still runs, players get no weapons.

**Design.** Collect all validation problems in a single pass, report them together, then publish a ready flag via `ServerEventBus`. `RoundService` gates `AssigningTeams` on this flag and aborts otherwise.

**New module — `src/Server/WeaponSystemState.lua`:**

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local WeaponSystemState = {}
local _ready: boolean? = nil

ServerEventBus:Connect("WeaponSystemReady", function(isReady: boolean)
    _ready = isReady
end)

function WeaponSystemState.IsReady(): boolean
    if _ready ~= nil then
        return _ready
    end
    --// Startup race: weapon executor hasn't fired yet. Bounded wait.
    local deadline = os.clock() + 5
    while _ready == nil and os.clock() < deadline do
        task.wait()
    end
    if _ready == nil then
        warn("[WeaponSystemState] No ready signal received within 5s — assuming not ready")
        return false
    end
    return _ready
end

return WeaponSystemState
```

**Change — `src/Server/WeaponDistributor/executor.server.lua`** — collect-then-fail validator; returns the full `guns` list so every tool in `GunModels` is validated and kept, not just the first:

```lua
local function validateWeapons(): (boolean, { string }?, { Tool }?, { Tool }?)
    local problems = {}
    local knives = {}
    local guns = {}

    local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
    if not knifeModels then
        table.insert(problems, "ReplicatedStorage.KnifeModels missing")
    else
        for _, child in knifeModels:GetChildren() do
            if child:IsA("Tool") then
                table.insert(knives, child)
            else
                table.insert(
                    problems,
                    `KnifeModels.{child.Name} is not a Tool (got {child.ClassName})`
                )
            end
        end
        if #knives == 0 then
            table.insert(problems, "KnifeModels contains zero Tools")
        end
    end

    local gunModels = ReplicatedStorage:FindFirstChild("GunModels")
    if not gunModels then
        table.insert(problems, "ReplicatedStorage.GunModels missing")
    else
        for _, child in gunModels:GetChildren() do
            if child:IsA("Tool") then
                table.insert(guns, child)
            else
                table.insert(
                    problems,
                    `GunModels.{child.Name} is not a Tool (got {child.ClassName})`
                )
            end
        end
        if #guns == 0 then
            table.insert(problems, "GunModels contains zero Tools")
        end
    end

    if #problems > 0 then
        return false, problems, nil, nil
    end
    return true, nil, knives, guns
end

local ok, problems, knives, guns = validateWeapons()
if not ok then
    warn("[WeaponDistributor] CRITICAL — weapon validation failed:")
    for _, msg in problems do
        warn(`  - {msg}`)
    end
    ServerEventBus:Fire("WeaponSystemReady", false)
    return
end

local initOk = WeaponDistributor.init(knives, guns)
if not initOk then
    warn("[WeaponDistributor] CRITICAL — init failed")
    ServerEventBus:Fire("WeaponSystemReady", false)
    return
end

ServerEventBus:Fire("WeaponSystemReady", true)
```

**Change — `src/Server/WeaponDistributor/init.lua`** — mirror the knife pipeline for guns so every validated gun is retained and selectable by name, and the pre-existing loadout-gunName-is-ignored bug is fixed:

```lua
local knifeTemplates: { [string]: Tool } = {}
local defaultKnifeTemplate: Tool? = nil
local gunTemplates: { [string]: Tool } = {}
local defaultGunTemplate: Tool? = nil

function WeaponDistributor.init(knives: { Tool }, guns: { Tool }): boolean
    if #knives == 0 then
        warn("[WeaponDistributor] No knife templates provided")
        return false
    end
    if #guns == 0 then
        warn("[WeaponDistributor] No gun templates provided")
        return false
    end

    for _, knife in knives do
        local knifeOk, knifeErr = WeaponModelValidator.validateKnife(knife)
        if not knifeOk then
            warn(`[WeaponDistributor] Knife template invalid: {knifeErr}`)
            return false
        end
    end
    for _, gun in guns do
        local gunOk, gunErr = WeaponModelValidator.validateGun(gun)
        if not gunOk then
            warn(`[WeaponDistributor] Gun template invalid: {gunErr}`)
            return false
        end
    end

    for i, knife in knives do
        ensureKnifeHitbox(knife)
        knifeTemplates[knife.Name] = knife
        if i == 1 then defaultKnifeTemplate = knife end
    end
    for i, gun in guns do
        ensureGunShootPoint(gun)
        gunTemplates[gun.Name] = gun
        if i == 1 then defaultGunTemplate = gun end
    end
    return true
end

function WeaponDistributor.distributeToPlayer(player: Player, knifeName: string?, gunName: string?)
    if not defaultKnifeTemplate or not defaultGunTemplate then
        warn(`[WeaponDistributor] Cannot distribute to {player.Name} — not initialized`)
        return
    end

    local backpack = player:FindFirstChildWhichIsA("Backpack")
    if not backpack then
        warn(`[WeaponDistributor] No Backpack found for {player.Name}`)
        return
    end

    local knifeTemplate = (knifeName and knifeTemplates[knifeName]) or defaultKnifeTemplate
    local gunTemplate = (gunName and gunTemplates[gunName]) or defaultGunTemplate

    local knife = knifeTemplate:Clone()
    knife:SetAttribute("IsKnife", true)
    knife.Parent = backpack

    local gun = gunTemplate:Clone()
    gun:SetAttribute("IsGun", true)
    gun.Parent = backpack
end

function WeaponDistributor._reset()
    knifeTemplates = {}
    defaultKnifeTemplate = nil
    gunTemplates = {}
    defaultGunTemplate = nil
end
```

**Change — `src/Server/WeaponDistributor/executor.server.lua`** `distribute` helper — pass both loadout names through:

```lua
local function distribute(player: Player)
    if not _roundActive then return end
    local loadout = TeleportMetadataService.GetLoadout(player.UserId)
    local knifeName = loadout and loadout.knifeName
    local gunName = loadout and loadout.gunName
    WeaponDistributor.distributeToPlayer(player, knifeName, gunName)
end
```

Since the validator fills every loadout field post-sanitization, `knifeName` and `gunName` will always be non-nil by the time this runs, and the `or default*Template` fallback is purely defensive.

**Change — `src/Server/RoundService/RoundOrchestrator.lua`** — add the require at the top of the file alongside existing requires:

```lua
local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
```

And gate `enterAssigningTeams`:

```lua
local function enterAssigningTeams(system)
    if system._waitTask then
        task.cancel(system._waitTask)
        system._waitTask = nil
    end

    if not WeaponSystemState.IsReady() then
        warn("[Round] Weapon system not ready — aborting round")
        system:_transition(Configs.GAME_STATES.Aborted)
        return
    end

    --// ...rest of existing logic
end
```

`Aborted` already transitions to `TeleportingOut` per `LEGAL_TRANSITIONS`, and with the retry-exhaustion kick in place, players are guaranteed to leave the server even if the lobby itself is unreachable.

## Files Changed

| File | Change |
| --- | --- |
| `src/Shared/Round/Configs.lua` | `CHARACTER_LOAD_TIMEOUT 10→7`, add `DEFAULT_LOADOUT`, add `KICK_REASONS` |
| `src/Server/RoundService/TeleportDataValidator.lua` | Return `(ok, err, sanitized)`; populate loadouts from cloned defaults |
| `src/Server/RoundService/executor.server.lua` | Kick on invalid data; look up BindableEvent; pass to `RoundSystem.new` |
| `src/Server/RoundService/init.lua` | `RoundSystem.new(metadata, positioningDoneEvent)` stores event |
| `src/Server/RoundService/RoundOrchestrator.lua` | Bounded positioning, weapon-ready gate in `enterAssigningTeams` |
| `src/Server/RoundService/TeleportUtility.lua` | Kick all players on retry exhaustion |
| `src/Server/WeaponDistributor/executor.server.lua` | Collect-then-fail validator returning full guns list; `WeaponSystemReady` signal; pass `gunName` through |
| `src/Server/WeaponDistributor/init.lua` | `init(knives, guns)` signature; `gunTemplates` dict + `defaultGunTemplate`; `distributeToPlayer` takes `gunName` |
| `src/Server/WeaponSystemState.lua` | New module holding ready flag, `IsReady()` with 5s startup wait |

## Testing

Repo has no unit test scaffold. Verification is integration via `mcp__robloxstudio__execute_luau` against a running edit-mode session. Drive each scenario from the Studio command bar and check server output for the expected warn/print sequence.

1. **Invalid teleport data** — set `TEST_MODE = false`, simulate `GetJoinData` returning malformed data, expect kick + no round created.
2. **Defaulted loadouts** — valid metadata but missing `loadouts`, expect distribution to use `DEFAULT_LOADOUT` clones.
3. **Character load timeout** — force a player into a state where `CharacterAdded` never fires (no-op their load). Expect kick at 7s, positioning loop unblocks, round continues with remaining players, disconnect pipeline runs.
4. **Teleport-out exhaustion** — point `LOBBY_PLACE_ID` at an invalid place, wait for `GameOver → TeleportingOut`, expect 3 attempts (1s, 2s, 4s backoff) then kick-all.
5. **Weapon validation** — remove `KnifeModels`, rename a knife Tool to a Model, boot server, expect full problem list + `Aborted` round on first match attempt.

## Reminders

- **`PositioningDone` BindableEvent path in `src/Server/RoundService/executor.server.lua` is a placeholder.** User will relocate it post-approval.
- **`DEFAULT_LOADOUT.knifeName` and `gunName` are placeholder strings.** User will set the real names post-approval.
