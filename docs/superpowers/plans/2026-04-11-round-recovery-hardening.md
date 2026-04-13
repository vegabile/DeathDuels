# Round Recovery Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert four silent-degradation paths in the round flow to explicit fail-closed behavior so no player gets stranded in a dead or half-initialized server.

**Architecture:** Kick on invalid join metadata, bound character loading with a single shared deadline + `WaitForChild("HumanoidRootPart")`, kick on teleport-out retry exhaustion, and gate round startup on a `WeaponSystemReady` flag published by the weapon executor after collect-then-fail validation. One new module (`WeaponSystemState`); the rest is surgical edits to existing files.

**Tech Stack:** Luau, Roblox Studio. Tests run via `mcp__robloxstudio__execute_luau` using the existing `check(label, condition, detail)` pattern from `RoundSystem.test.lua` and `WeaponDistributor.test.lua`.

**Spec:** `docs/superpowers/specs/2026-04-11-round-recovery-hardening-design.md`

---

## Orientation

Every task below assumes the engineer has zero context. Conventions:

- **`--//` comments only.** Never `--`. Comments only for non-obvious WHY.
- **Never `Instance.new`** for UI-like things. A `BindableEvent` used across the project for round coordination is looked up at a placeholder path, not constructed.
- **Never silent return.** Any non-happy path must `warn` with a clear reason first.
- **`assert` is banned.** Use `warn` + return.
- **File map:** `src/Server` → `ServerScriptService`, `src/Client` → `StarterPlayerScripts`, `src/Shared` → `ReplicatedStorage`.
- **Test pattern:** Each test file is self-contained, requires its target via `require(ServerScriptService.X.Y)`, uses a local `check(label, condition, detail?)` helper, and is run via `mcp__robloxstudio__execute_luau` in the Studio edit environment — never via a playtest.

Commit after each logical unit lands and its tests pass. Small commits, frequent.

---

## Task 1: Add config entries

**Files:**
- Modify: `src/Shared/Round/Configs.lua`

- [ ] **Step 1: Change `CHARACTER_LOAD_TIMEOUT` from 10 to 7 and add `DEFAULT_LOADOUT` + `KICK_REASONS`**

Open `src/Shared/Round/Configs.lua`. Change the existing `CHARACTER_LOAD_TIMEOUT = 10` line to `CHARACTER_LOAD_TIMEOUT = 7`. Then add these two new top-level entries inside the returned table (placement doesn't matter, but group them with `RESPAWN_DELAY` for readability):

```lua
    CHARACTER_LOAD_TIMEOUT = 7,

    DEFAULT_LOADOUT = {
        knifeName = "Default",  --// placeholder — user will edit post-approval
        gunName = "Default",
    },

    KICK_REASONS = {
        InvalidTeleportData = "Invalid match data. Returning to lobby.",
        CharacterLoadTimeout = "Character failed to load in time.",
        TeleportOutFailed = "Unable to return to lobby. Please rejoin.",
    },
```

- [ ] **Step 2: Verify config loads cleanly**

Run this via `mcp__robloxstudio__execute_luau`:

```lua
local Configs = require(game:GetService("ReplicatedStorage").Round.Configs)
print("CHARACTER_LOAD_TIMEOUT:", Configs.CHARACTER_LOAD_TIMEOUT)
print("DEFAULT_LOADOUT.knifeName:", Configs.DEFAULT_LOADOUT.knifeName)
print("DEFAULT_LOADOUT.gunName:", Configs.DEFAULT_LOADOUT.gunName)
print("KICK_REASONS.InvalidTeleportData:", Configs.KICK_REASONS.InvalidTeleportData)
print("KICK_REASONS.CharacterLoadTimeout:", Configs.KICK_REASONS.CharacterLoadTimeout)
print("KICK_REASONS.TeleportOutFailed:", Configs.KICK_REASONS.TeleportOutFailed)
```

Expected output:
```
CHARACTER_LOAD_TIMEOUT: 7
DEFAULT_LOADOUT.knifeName: Default
DEFAULT_LOADOUT.gunName: Default
KICK_REASONS.InvalidTeleportData: Invalid match data. Returning to lobby.
KICK_REASONS.CharacterLoadTimeout: Character failed to load in time.
KICK_REASONS.TeleportOutFailed: Unable to return to lobby. Please rejoin.
```

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Round/Configs.lua
git commit -m "feat: add CHARACTER_LOAD_TIMEOUT=7, DEFAULT_LOADOUT, KICK_REASONS"
```

---

## Task 2: Update `TeleportDataValidator` to return a sanitized copy with defaulted loadouts

**Files:**
- Modify: `src/Server/RoundService/TeleportDataValidator.lua`

The current validator returns `(ok, err)` and rejects missing `loadouts` outright. It needs to return `(ok, err, sanitized)`, deep-copy the input, and fill every missing loadout field from `Configs.DEFAULT_LOADOUT` clones. Critical fields (`teamOnePlayers`, `teamTwoPlayers`, `queueType`, `mapName`, `timestamp`) still fail hard.

- [ ] **Step 1: Replace the whole file with the new implementation**

Write this to `src/Server/RoundService/TeleportDataValidator.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapValidator = require(ReplicatedStorage.Map.MapValidator)
local Configs = require(ReplicatedStorage.Round.Configs)

local TeleportDataValidator = {}

local function validatePlayerList(list: any, fieldName: string): (boolean, string?)
    if type(list) ~= "table" then
        return false, `{fieldName} is not a table`
    end
    if #list == 0 then
        return false, `{fieldName} is empty`
    end
    for i, entry in list do
        if type(entry) ~= "table" then
            return false, `{fieldName}[{i}] is not a table`
        end
        if type(entry.UserId) ~= "number" then
            return false, `{fieldName}[{i}].UserId is not a number`
        end
        if type(entry.Name) ~= "string" then
            return false, `{fieldName}[{i}].Name is not a string`
        end
    end
    return true, nil
end

local function cloneDefaultLoadout()
    return {
        knifeName = Configs.DEFAULT_LOADOUT.knifeName,
        gunName = Configs.DEFAULT_LOADOUT.gunName,
    }
end

--// Shallow copy teams so the sanitized table can be mutated without touching
--// the caller's data. Entries themselves are kept by reference — the fields
--// we read (UserId, Name) are immutable per-entry.
local function cloneTeamList(list)
    local out = {}
    for i, entry in list do out[i] = entry end
    return out
end

local function fillLoadouts(sanitized)
    if type(sanitized.loadouts) ~= "table" then
        sanitized.loadouts = {}
    else
        --// Copy so we don't mutate the caller's loadouts table.
        local copy = {}
        for k, v in sanitized.loadouts do
            copy[k] = { knifeName = v.knifeName, gunName = v.gunName }
        end
        sanitized.loadouts = copy
    end

    local function fillFor(entry)
        local key = tostring(entry.UserId)
        local loadout = sanitized.loadouts[key]
        if not loadout then
            sanitized.loadouts[key] = cloneDefaultLoadout()
            return
        end
        if loadout.knifeName == nil then
            loadout.knifeName = Configs.DEFAULT_LOADOUT.knifeName
        end
        if loadout.gunName == nil then
            loadout.gunName = Configs.DEFAULT_LOADOUT.gunName
        end
    end
    for _, entry in sanitized.teamOnePlayers do fillFor(entry) end
    for _, entry in sanitized.teamTwoPlayers do fillFor(entry) end
end

function TeleportDataValidator.validate(teleportData: any): (boolean, string?, { [string]: any }?)
    if type(teleportData) ~= "table" then
        return false, "Teleport data is not a table", nil
    end

    local ok, err = validatePlayerList(teleportData.teamOnePlayers, "teamOnePlayers")
    if not ok then return false, err, nil end

    ok, err = validatePlayerList(teleportData.teamTwoPlayers, "teamTwoPlayers")
    if not ok then return false, err, nil end

    if type(teleportData.queueType) ~= "number" then
        return false, "queueType is not a number", nil
    end
    ok, err = MapValidator.validate(teleportData.mapName)
    if not ok then return false, err, nil end
    if type(teleportData.timestamp) ~= "number" then
        return false, "timestamp is not a number", nil
    end

    local sanitized = {
        teamOnePlayers = cloneTeamList(teleportData.teamOnePlayers),
        teamTwoPlayers = cloneTeamList(teleportData.teamTwoPlayers),
        queueType = teleportData.queueType,
        mapName = teleportData.mapName,
        timestamp = teleportData.timestamp,
        loadouts = teleportData.loadouts,
    }
    fillLoadouts(sanitized)

    return true, nil, sanitized
end

return TeleportDataValidator
```

Key differences from the current file:

- New require on `Configs`.
- Return type is now `(boolean, string?, { [string]: any }?)`.
- On success, returns a sanitized copy whose loadouts table and per-entry fields are guaranteed populated.
- The old `loadouts` type check that failed hard is removed — a missing `loadouts` is now filled from defaults.

- [ ] **Step 2: Write the validator unit test**

Create `src/Server/RoundService/TeleportDataValidator.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TeleportDataValidator = require(ServerScriptService.RoundService.TeleportDataValidator)
local Configs = require(ReplicatedStorage.Round.Configs)

local passed = 0
local failed = 0

local function check(label: string, condition: boolean, detail: string?)
    if condition then
        print(`PASS: {label}`)
        passed += 1
    else
        print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
        failed += 1
    end
end

local function makeValidBase()
    return {
        teamOnePlayers = { { UserId = 1, Name = "Alice" } },
        teamTwoPlayers = { { UserId = 2, Name = "Bob" } },
        queueType = 1,
        mapName = "TestMap",  --// assumes TestMap exists in ReplicatedStorage.Maps
        timestamp = os.time(),
    }
end

-- ─── Critical fields reject ─────────────────────────────────────────────────
do
    local ok, err, sanitized = TeleportDataValidator.validate(nil)
    check("nil input → false", not ok)
    check("nil input → sanitized nil", sanitized == nil)
    check("nil input → error message", type(err) == "string")
end

do
    local data = makeValidBase()
    data.teamOnePlayers = nil
    local ok = TeleportDataValidator.validate(data)
    check("missing teamOnePlayers → false", not ok)
end

do
    local data = makeValidBase()
    data.mapName = nil
    local ok = TeleportDataValidator.validate(data)
    check("missing mapName → false", not ok)
end

do
    local data = makeValidBase()
    data.queueType = "not-a-number"
    local ok = TeleportDataValidator.validate(data)
    check("invalid queueType → false", not ok)
end

do
    local data = makeValidBase()
    data.timestamp = nil
    local ok = TeleportDataValidator.validate(data)
    check("missing timestamp → false", not ok)
end

-- ─── Loadouts defaulting ────────────────────────────────────────────────────
do
    --// Missing loadouts table → filled for both players
    local data = makeValidBase()
    local ok, _, sanitized = TeleportDataValidator.validate(data)
    check("missing loadouts → ok=true", ok)
    check("sanitized loadouts is table", type(sanitized.loadouts) == "table")
    check("sanitized loadouts['1'] populated", sanitized.loadouts["1"] ~= nil)
    check("sanitized loadouts['2'] populated", sanitized.loadouts["2"] ~= nil)
    check("sanitized loadouts['1'].knifeName = default",
        sanitized.loadouts["1"].knifeName == Configs.DEFAULT_LOADOUT.knifeName)
    check("sanitized loadouts['1'].gunName = default",
        sanitized.loadouts["1"].gunName == Configs.DEFAULT_LOADOUT.gunName)
end

do
    --// loadouts non-table → treated as missing
    local data = makeValidBase()
    data.loadouts = "nope"
    local ok, _, sanitized = TeleportDataValidator.validate(data)
    check("non-table loadouts → ok=true", ok)
    check("non-table loadouts → filled", sanitized.loadouts["1"] ~= nil)
end

do
    --// Partial loadouts: one player present, other missing
    local data = makeValidBase()
    data.loadouts = {
        ["1"] = { knifeName = "Shiv", gunName = "Pistol" },
    }
    local ok, _, sanitized = TeleportDataValidator.validate(data)
    check("partial loadouts → ok=true", ok)
    check("provided entry preserved knifeName",
        sanitized.loadouts["1"].knifeName == "Shiv")
    check("provided entry preserved gunName",
        sanitized.loadouts["1"].gunName == "Pistol")
    check("missing entry filled with default",
        sanitized.loadouts["2"].knifeName == Configs.DEFAULT_LOADOUT.knifeName)
end

do
    --// Nil field within a present entry → filled from default
    local data = makeValidBase()
    data.loadouts = {
        ["1"] = { knifeName = "Shiv" },  --// gunName missing
        ["2"] = { gunName = "Pistol" },  --// knifeName missing
    }
    local ok, _, sanitized = TeleportDataValidator.validate(data)
    check("nil field → ok=true", ok)
    check("player 1 gunName defaulted",
        sanitized.loadouts["1"].gunName == Configs.DEFAULT_LOADOUT.gunName)
    check("player 2 knifeName defaulted",
        sanitized.loadouts["2"].knifeName == Configs.DEFAULT_LOADOUT.knifeName)
    check("player 1 knifeName preserved",
        sanitized.loadouts["1"].knifeName == "Shiv")
end

do
    --// Mutation of sanitized must not touch the caller's table
    local data = makeValidBase()
    data.loadouts = { ["1"] = { knifeName = "Shiv", gunName = "Pistol" } }
    local ok, _, sanitized = TeleportDataValidator.validate(data)
    sanitized.loadouts["1"].knifeName = "Mutated"
    check("mutation isolated from caller", data.loadouts["1"].knifeName == "Shiv")
end

do
    --// Config must not be mutable through sanitized
    local data = makeValidBase()
    local _, _, sanitized = TeleportDataValidator.validate(data)
    sanitized.loadouts["1"].knifeName = "Mutated"
    check("config DEFAULT_LOADOUT.knifeName unchanged",
        Configs.DEFAULT_LOADOUT.knifeName == "Default")
end

print(`\n──── TeleportDataValidator: {passed} passed, {failed} failed ────`)
```

- [ ] **Step 3: Run the test**

Run `src/Server/RoundService/TeleportDataValidator.test.lua` via `mcp__robloxstudio__execute_luau`.

Expected: all tests PASS, footer shows `0 failed`.

Note: the `TestMap` requirement in `makeValidBase()` depends on `ReplicatedStorage.Maps.TestMap` existing. If it doesn't, substitute a map name that does. If no valid map exists in Studio, stub the `MapValidator` require in the test via a small wrapper — but check first, the TEST_MODE branch already uses "TestMap" so it almost certainly exists.

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/TeleportDataValidator.lua src/Server/RoundService/TeleportDataValidator.test.lua
git commit -m "feat: TeleportDataValidator returns sanitized copy with defaulted loadouts"
```

---

## Task 3: `RoundService` executor kicks on invalid data and looks up the positioning BindableEvent

**Files:**
- Modify: `src/Server/RoundService/executor.server.lua`

- [ ] **Step 1: Update the real-data branch of `setupPlayer` to kick and use sanitized data**

Open `src/Server/RoundService/executor.server.lua`. Find the block around lines 33-46:

```lua
    else
        local joinData = player:GetJoinData()
        teleportData = joinData and joinData.TeleportData

        if not teleportData then
            warn(`[Round] No teleport data for {player.Name}`)
            return
        end

        local ok, err = TeleportDataValidator.validate(teleportData)
        if not ok then
            warn(`[Round] Invalid teleport data for {player.Name}: {err}`)
            return
        end
    end
```

Replace with:

```lua
    else
        local joinData = player:GetJoinData()
        local rawData = joinData and joinData.TeleportData

        local ok, err, sanitized = TeleportDataValidator.validate(rawData)
        if not ok then
            warn(`[Round] Invalid teleport data for {player.Name}: {err}`)
            player:Kick(Configs.KICK_REASONS.InvalidTeleportData)
            return
        end
        teleportData = sanitized
    end
```

Note:
- The `if not teleportData then ... return end` branch folds into the validator — `validate(nil)` returns `false, "Teleport data is not a table", nil` which fires the kick.
- `Configs` is already required at the top of this file — no new import.

- [ ] **Step 2: Add the BindableEvent lookup above `setupPlayer`**

Immediately after the `local roundSystem = nil` line near the top of the file, add:

```lua
local ServerStorage = game:GetService("ServerStorage")
--// PLACEHOLDER PATH — user will relocate this BindableEvent post-approval.
local positioningDoneEvent =
    ServerStorage:WaitForChild("RoundEvents"):WaitForChild("PositioningDone")
```

- [ ] **Step 3: Pass the event into `RoundService.new`**

Find the line:

```lua
roundSystem = RoundService.new(teleportData)
```

Replace with:

```lua
roundSystem = RoundService.new(teleportData, positioningDoneEvent)
```

- [ ] **Step 4: Create the placeholder BindableEvent in Studio**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ServerStorage = game:GetService("ServerStorage")
local folder = ServerStorage:FindFirstChild("RoundEvents") or Instance.new("Folder")
folder.Name = "RoundEvents"
folder.Parent = ServerStorage

local existing = folder:FindFirstChild("PositioningDone")
if not existing then
    local ev = Instance.new("BindableEvent")
    ev.Name = "PositioningDone"
    ev.Parent = folder
end
print("[setup] ServerStorage.RoundEvents.PositioningDone ready")
```

This is a one-time Studio setup, not production code. The spec flags the path as a placeholder.

- [ ] **Step 5: Commit**

```bash
git add src/Server/RoundService/executor.server.lua
git commit -m "feat: kick on invalid teleport data; look up positioning BindableEvent"
```

---

## Task 4: `RoundSystem.new` accepts and stores the positioning BindableEvent

**Files:**
- Modify: `src/Server/RoundService/init.lua`

- [ ] **Step 1: Update the constructor signature**

Open `src/Server/RoundService/init.lua`. Find:

```lua
function RoundSystem.new(metadata: TeleportMetadata)
    TeleportMetadataService.Initialize(metadata)

    local self = setmetatable({}, RoundSystem)

    self._metadata = metadata
```

Replace with:

```lua
function RoundSystem.new(metadata: TeleportMetadata, positioningDoneEvent: BindableEvent)
    TeleportMetadataService.Initialize(metadata)

    local self = setmetatable({}, RoundSystem)

    self._metadata = metadata
    self._positioningDoneEvent = positioningDoneEvent
```

No other changes to this file.

- [ ] **Step 2: Commit**

```bash
git add src/Server/RoundService/init.lua
git commit -m "feat: RoundSystem.new accepts positioning BindableEvent"
```

---

## Task 5: Bounded, failure-safe `loadAndPositionPlayers` in `RoundOrchestrator`

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

This replaces the unbounded `CharacterAdded:Wait()` loop with a single-deadline `WaitForChild("HumanoidRootPart")` gate and guarantees `remaining` is decremented on every exit path. On timeout, kick the player — the existing `PlayerRemoving` handler runs `UnregisterPlayer`, which handles the disconnect pipeline.

- [ ] **Step 1: Replace `loadAndPositionPlayers`**

Open `src/Server/RoundService/RoundOrchestrator.lua`. Find the `loadAndPositionPlayers` function (starts near line 38). Replace the entire function with:

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

                --// Wait for HumanoidRootPart to replicate within the remaining
                --// deadline. CharacterAdded can fire before HRP is available,
                --// so the HRP wait is the real "usable character" signal.
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

Why the `if remaining > 0` guard matters: if every spawned task completes synchronously (e.g. all characters already exist with HRP), `remaining` hits zero before the main thread reaches `Event:Wait()`. Without the guard, the Wait call blocks forever.

- [ ] **Step 2: Smoke-check in Studio**

Run a small script via `mcp__robloxstudio__execute_luau` to confirm the orchestrator still requires cleanly and the BindableEvent is available:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ok, err = pcall(function()
    require(ServerScriptService.RoundService.RoundOrchestrator)
end)
print("RoundOrchestrator require ok:", ok, err)

local ev = ServerStorage:FindFirstChild("RoundEvents")
    and ServerStorage.RoundEvents:FindFirstChild("PositioningDone")
print("PositioningDone exists:", ev ~= nil)
print("PositioningDone isA BindableEvent:",
    ev ~= nil and ev:IsA("BindableEvent"))
```

Expected: both lines show true, no error.

- [ ] **Step 3: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "fix: bound character load, guarantee counter decrement, kick on timeout"
```

---

## Task 6: Kick on teleport-out retry exhaustion

**Files:**
- Modify: `src/Server/RoundService/TeleportUtility.lua`

- [ ] **Step 1: Update `teleportPlayersWithRetry` exhaustion branch**

Open `src/Server/RoundService/TeleportUtility.lua`. Find the block:

```lua
        else
            warn(`[TeleportUtility] All {Configs.RETRY_COUNT} attempts exhausted: {err}`)
            return false, err
        end
```

Replace with:

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

No other changes. The caller (`RoundOrchestrator.enterTeleportingOut`) already handles `not ok` with a warn; the kick happens before that warn runs.

- [ ] **Step 2: Verify the module still requires cleanly**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportUtility = require(ServerScriptService.RoundService.TeleportUtility)
print("teleportPlayersWithRetry type:", type(TeleportUtility.teleportPlayersWithRetry))
```

Expected: `teleportPlayersWithRetry type: function`

- [ ] **Step 3: Commit**

```bash
git add src/Server/RoundService/TeleportUtility.lua
git commit -m "fix: kick players when lobby teleport retries are exhausted"
```

---

## Task 7: `WeaponDistributor/init.lua` — enumerate guns like knives

**Files:**
- Modify: `src/Server/WeaponDistributor/init.lua`
- Modify: `src/Server/WeaponDistributor/WeaponDistributor.test.lua`

Goal: make `init(knives, guns)` accept a list of guns, mirror the knife template pipeline (validate all, build a name-keyed dict, remember first as default), and extend `distributeToPlayer` to accept a `gunName`.

- [ ] **Step 1: Replace `init` and `distributeToPlayer` plus the reset helper**

Open `src/Server/WeaponDistributor/init.lua`. Find these state declarations at the top:

```lua
local knifeTemplates: { [string]: Tool } = {}
local defaultKnifeTemplate: Tool? = nil
local gunTemplate: Tool? = nil
```

Replace with:

```lua
local knifeTemplates: { [string]: Tool } = {}
local defaultKnifeTemplate: Tool? = nil
local gunTemplates: { [string]: Tool } = {}
local defaultGunTemplate: Tool? = nil
```

Find the `WeaponDistributor.init` function (starts ~line 61). Replace the entire function with:

```lua
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
```

Find the `WeaponDistributor.distributeToPlayer` function (~line 94). Replace with:

```lua
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
```

Find the `WeaponDistributor._reset` function at the bottom. Replace with:

```lua
function WeaponDistributor._reset()
    knifeTemplates = {}
    defaultKnifeTemplate = nil
    gunTemplates = {}
    defaultGunTemplate = nil
end
```

- [ ] **Step 2: Update the existing test file for the new signature**

Open `src/Server/WeaponDistributor/WeaponDistributor.test.lua`. The existing tests already pass knives as a list `{knife}` but pass a single `gun` argument. Every call site needs the gun wrapped in a list.

Find-and-replace across this file (manually, since these are not one-off strings):

| Before | After |
| --- | --- |
| `WeaponDistributor.init({badKnife}, validGun)` | `WeaponDistributor.init({badKnife}, {validGun})` |
| `WeaponDistributor.init({validKnife}, badGun)` | `WeaponDistributor.init({validKnife}, {badGun})` |
| `WeaponDistributor.init({knifeNoHitbox}, gun)` | `WeaponDistributor.init({knifeNoHitbox}, {gun})` |
| `WeaponDistributor.init({knifeWithHitbox}, gun2)` | `WeaponDistributor.init({knifeWithHitbox}, {gun2})` |
| `WeaponDistributor.init({knife}, gunWithAttach)` | `WeaponDistributor.init({knife}, {gunWithAttach})` |
| `WeaponDistributor.init({knife2}, gunNoAttach)` | `WeaponDistributor.init({knife2}, {gunNoAttach})` |
| `WeaponDistributor.init({knife3}, gunWithShootPoint)` | `WeaponDistributor.init({knife3}, {gunWithShootPoint})` |
| `WeaponDistributor.init({knife}, gun)` | `WeaponDistributor.init({knife}, {gun})` |
| `WeaponDistributor.init({knifeA, knifeB}, gun)` | `WeaponDistributor.init({knifeA, knifeB}, {gun})` |

After the replacements, add this block at the end of the file (before the final `print` summary line) to cover the new gun-by-name path:

```lua
-- ─── Gun selection by name ────────────────────────────────────────────────────

do
    WeaponDistributor._reset()

    local knife = makeTool("KnifeForGunSelect")
    addHandle(knife)

    local gunA = makeTool("GunAlpha")
    local gunAHandle = addHandle(gunA)
    gunAHandle.Size = Vector3.new(0.2, 1.0, 1.5)
    addAttachment(gunAHandle, "ShootPoint")

    local gunB = makeTool("GunBeta")
    local gunBHandle = addHandle(gunB)
    gunBHandle.Size = Vector3.new(0.2, 1.0, 1.5)
    addAttachment(gunBHandle, "ShootPoint")

    local ok = WeaponDistributor.init({knife}, {gunA, gunB})
    check("init multi-gun → true", ok)

    local mockPlayer, backpack = makePlayerWithBackpack()
    WeaponDistributor.distributeToPlayer(mockPlayer, nil, "GunBeta")

    local delivered
    for _, child in backpack:GetChildren() do
        if child:GetAttribute("IsGun") then delivered = child end
    end
    check("distributeToPlayer picks gun by name", delivered ~= nil and delivered.Name == "GunBeta")

    cleanAll()
end

do
    WeaponDistributor._reset()

    local knife = makeTool("KnifeForGunFallback")
    addHandle(knife)

    local gunA = makeTool("GunAlpha2")
    local gunAHandle = addHandle(gunA)
    gunAHandle.Size = Vector3.new(0.2, 1.0, 1.5)
    addAttachment(gunAHandle, "ShootPoint")

    WeaponDistributor.init({knife}, {gunA})

    local mockPlayer, backpack = makePlayerWithBackpack()
    WeaponDistributor.distributeToPlayer(mockPlayer, nil, "NonExistentGun")

    local delivered
    for _, child in backpack:GetChildren() do
        if child:GetAttribute("IsGun") then delivered = child end
    end
    check("unknown gunName → falls back to default", delivered ~= nil and delivered.Name == "GunAlpha2")

    cleanAll()
end
```

- [ ] **Step 3: Run the tests**

Run `src/Server/WeaponDistributor/WeaponDistributor.test.lua` via `mcp__robloxstudio__execute_luau`.

Expected: all existing tests still pass, plus the two new gun-selection tests pass. Footer shows `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add src/Server/WeaponDistributor/init.lua src/Server/WeaponDistributor/WeaponDistributor.test.lua
git commit -m "feat: WeaponDistributor enumerates guns like knives, selects by name"
```

---

## Task 8: `WeaponSystemState` module

**Files:**
- Create: `src/Server/WeaponSystemState/init.lua`

The module listens to a `WeaponSystemReady` signal on `ServerEventBus` and exposes a blocking `IsReady()` with a 5-second startup deadline. Uses a folder-style module (`init.lua`) to match the project convention.

- [ ] **Step 1: Create the module**

Create `src/Server/WeaponSystemState/init.lua`:

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
    --// Startup race: weapon executor may not have fired yet. Bounded wait.
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

--// Test-only: resets state between tests.
function WeaponSystemState._reset()
    _ready = nil
end

return WeaponSystemState
```

- [ ] **Step 2: Write the unit test**

Create `src/Server/WeaponSystemState/WeaponSystemState.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ServerScriptService = game:GetService("ServerScriptService")

local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local passed = 0
local failed = 0

local function check(label: string, condition: boolean, detail: string?)
    if condition then
        print(`PASS: {label}`)
        passed += 1
    else
        print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
        failed += 1
    end
end

-- ─── Positive signal ─────────────────────────────────────────────────────────
do
    WeaponSystemState._reset()
    ServerEventBus:Fire("WeaponSystemReady", true)
    task.wait()  --// let the listener run
    check("IsReady() returns true after positive signal", WeaponSystemState.IsReady())
end

-- ─── Negative signal ─────────────────────────────────────────────────────────
do
    WeaponSystemState._reset()
    ServerEventBus:Fire("WeaponSystemReady", false)
    task.wait()
    check("IsReady() returns false after negative signal", not WeaponSystemState.IsReady())
end

-- ─── Signal after call starts (race) ─────────────────────────────────────────
do
    WeaponSystemState._reset()
    local result
    task.spawn(function()
        result = WeaponSystemState.IsReady()
    end)
    task.wait(0.1)
    ServerEventBus:Fire("WeaponSystemReady", true)
    task.wait(0.1)
    check("IsReady() resolves when signal arrives mid-wait", result == true)
end

-- ─── Startup timeout ─────────────────────────────────────────────────────────
do
    WeaponSystemState._reset()
    local start = os.clock()
    local ready = WeaponSystemState.IsReady()
    local elapsed = os.clock() - start
    check("IsReady() returns false on timeout", not ready)
    check("IsReady() honors ~5s deadline", elapsed >= 4.5 and elapsed <= 6.0,
        `elapsed = {elapsed}`)
end

print(`\n──── WeaponSystemState: {passed} passed, {failed} failed ────`)
```

- [ ] **Step 3: Run the test**

Run `src/Server/WeaponSystemState/WeaponSystemState.test.lua` via `mcp__robloxstudio__execute_luau`.

Expected: all checks pass. The timeout test will take ~5s — that's intentional.

- [ ] **Step 4: Commit**

```bash
git add src/Server/WeaponSystemState/init.lua src/Server/WeaponSystemState/WeaponSystemState.test.lua
git commit -m "feat: WeaponSystemState module exposes ready flag with startup wait"
```

---

## Task 9: `WeaponDistributor/executor.server.lua` — collect-then-fail validator, signal ready, pass gunName through

**Files:**
- Modify: `src/Server/WeaponDistributor/executor.server.lua`

The current executor has five independent `warn + return` branches. Replace them with one validator that accumulates every problem and reports them together, then fires `WeaponSystemReady` via `ServerEventBus` on every exit path. Also pass `loadout.gunName` into `distributeToPlayer`.

- [ ] **Step 1: Replace the top-of-file setup block**

Open `src/Server/WeaponDistributor/executor.server.lua`. Find the block from line 14 through line 48 (starting with `local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")` and ending with `local ok = WeaponDistributor.init(knives, gun) ... end`). Replace with:

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

local validationOk, problems, knives, guns = validateWeapons()
if not validationOk then
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

- [ ] **Step 2: Update `distribute` to pass `gunName`**

Still in `src/Server/WeaponDistributor/executor.server.lua`, find:

```lua
local function distribute(player: Player)
    if not _roundActive then return end
    local loadout = TeleportMetadataService.GetLoadout(player.UserId)
    local knifeName = loadout and loadout.knifeName
    WeaponDistributor.distributeToPlayer(player, knifeName)
end
```

Replace with:

```lua
local function distribute(player: Player)
    if not _roundActive then return end
    local loadout = TeleportMetadataService.GetLoadout(player.UserId)
    local knifeName = loadout and loadout.knifeName
    local gunName = loadout and loadout.gunName
    WeaponDistributor.distributeToPlayer(player, knifeName, gunName)
end
```

- [ ] **Step 3: Smoke-check boot**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
print("WeaponSystemState.IsReady:", WeaponSystemState.IsReady())
```

Expected: `true` (assuming `KnifeModels` and `GunModels` are present and populated in `ReplicatedStorage` — which they should be for a working dev build).

If it prints `false`, check the server output for the problem list and either fix the asset layout or confirm that the validator reported the correct issue.

- [ ] **Step 4: Commit**

```bash
git add src/Server/WeaponDistributor/executor.server.lua
git commit -m "feat: weapon executor collect-then-fail validation, signal ready, forward gunName"
```

---

## Task 10: `RoundOrchestrator` gates `enterAssigningTeams` on weapon readiness

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Add the require at the top of the file**

Open `src/Server/RoundService/RoundOrchestrator.lua`. Find the existing require block at the top:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
```

Add one line after `ServerEventBus`:

```lua
local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
```

- [ ] **Step 2: Add the readiness gate inside `enterAssigningTeams`**

Find the `enterAssigningTeams` function. The current first lines are:

```lua
local function enterAssigningTeams(system)
    if system._waitTask then
        task.cancel(system._waitTask)
        system._waitTask = nil
    end

    local mapName = TeleportMetadataService.GetMapName()
```

Insert the gate between the `_waitTask` cleanup and the `mapName` lookup:

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

    local mapName = TeleportMetadataService.GetMapName()
```

No other changes to this function.

- [ ] **Step 3: Smoke-check require**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ok, err = pcall(function()
    require(ServerScriptService.RoundService.RoundOrchestrator)
end)
print("RoundOrchestrator reload ok:", ok, err)
```

Expected: `ok: true`.

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat: gate enterAssigningTeams on WeaponSystemState.IsReady()"
```

---

## Task 11: End-to-end integration verification in Studio

No code changes — these are manual verification scripts run via `mcp__robloxstudio__execute_luau`. If any step fails, stop and fix the relevant task before moving on.

- [ ] **Step 1: Invalid-teleport-data path**

Temporarily set `GlobalConfigs.TEST_MODE = false` in `src/Shared/GlobalConfigs.lua`, reload. Simulate a bad payload by calling the validator directly with an intentionally broken table and confirm it rejects:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportDataValidator = require(ServerScriptService.RoundService.TeleportDataValidator)
local ok, err = TeleportDataValidator.validate({ mapName = "TestMap" })
print("ok:", ok, "err:", err)
```

Expected: `ok: false  err: teamOnePlayers is not a table`.

Restore `TEST_MODE = true` before moving on.

- [ ] **Step 2: Loadout defaulting**

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportDataValidator = require(ServerScriptService.RoundService.TeleportDataValidator)
local Configs = require(ReplicatedStorage.Round.Configs)

local data = {
    teamOnePlayers = { { UserId = 1, Name = "Alice" } },
    teamTwoPlayers = { { UserId = 2, Name = "Bob" } },
    queueType = 1,
    mapName = "TestMap",
    timestamp = os.time(),
}
local ok, _, sanitized = TeleportDataValidator.validate(data)
print("ok:", ok)
print("loadouts.1:", sanitized.loadouts["1"].knifeName, sanitized.loadouts["1"].gunName)
print("loadouts.2:", sanitized.loadouts["2"].knifeName, sanitized.loadouts["2"].gunName)
print("default config:", Configs.DEFAULT_LOADOUT.knifeName, Configs.DEFAULT_LOADOUT.gunName)
```

Expected: all four loadout fields equal the `DEFAULT_LOADOUT` values; `ok: true`.

- [ ] **Step 3: Weapon-ready flag resolves true in a healthy boot**

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
print("IsReady:", WeaponSystemState.IsReady())
```

Expected: `true`.

- [ ] **Step 4: Weapon-ready flag resolves false when assets are broken**

In Studio, temporarily rename `ReplicatedStorage.GunModels` to `GunModels_Disabled`. Run this script:

```lua
local ServerStorage = game:GetService("ServerStorage")
--// Reset ready state the quick way: simulate a fresh session by re-requiring.
--// In a production scenario this would mean restarting the server entirely.
print("Manually observe server output for the weapon validation failure list.")
```

Open the server output. Expected: a `CRITICAL — weapon validation failed:` line followed by bullet lines. Restore `GunModels` to its original name when done.

- [ ] **Step 5: Character-load timeout (observational)**

This requires a live session and a player, so it's inherently harder to test in pure edit mode. If you can, start a playtest with two players and block character loading for one of them (e.g. by deleting their spawn character in the Explorer before positioning starts). Observe:

1. Positioning loop unblocks after ~7s instead of hanging.
2. The blocked player is kicked with the "Character failed to load in time." reason.
3. The round continues for the remaining player(s).
4. `RoundSystem._disconnectedStats` contains an entry for the kicked player.

If playtest isn't available in this workflow, record this as "verified by code inspection against spec invariants section."

- [ ] **Step 6: Teleport-out retry kick (observational)**

Temporarily point `Configs.LOBBY_PLACE_ID` at an invalid value (e.g. `-1`) in a local branch, run a full round to `GameOver → TeleportingOut`, and confirm:

1. Three attempts happen with 1s, 2s, 4s gaps (7 seconds total).
2. Final warn line lists all attempts exhausted.
3. Every player is kicked with the "Unable to return to lobby." reason.

Restore `LOBBY_PLACE_ID` to its original value when done.

- [ ] **Step 7: Final commit — no code changes, just close out**

If any manual test revealed a regression, fix it, commit the fix, and re-run the affected verification. Otherwise nothing to commit here — the plan is complete.

---

## Self-Review Notes

- **Spec coverage:**
    - Config changes → Task 1.
    - Teleport-data validation + defaulting (spec §1) → Task 2.
    - Executor kick + BindableEvent (spec §2 part 1) → Task 3.
    - `RoundSystem.new` signature (spec §2 part 2) → Task 4.
    - Bounded `loadAndPositionPlayers` (spec §2 part 3) → Task 5.
    - Teleport-out exhaustion kick (spec §3) → Task 6.
    - `WeaponDistributor/init.lua` gun pipeline (spec §4 part 2) → Task 7.
    - `WeaponSystemState` (spec §4 part 1) → Task 8.
    - Weapon executor validator + ready signal + gunName passthrough (spec §4 parts 3-4) → Task 9.
    - `enterAssigningTeams` gate (spec §4 part 5) → Task 10.
    - Testing section → Task 11 and per-task verification steps.
- **Placeholder scan:** the two explicit "placeholder" strings (`DEFAULT_LOADOUT` values and the `ServerStorage.RoundEvents.PositioningDone` path) are the user's flagged post-approval edits, called out in the spec's Reminders section. No other TBDs.
- **Type consistency:** `init(knives, guns)`, `distributeToPlayer(player, knifeName, gunName)`, `validate(teleportData)` return `(boolean, string?, sanitized?)`, and `RoundSystem.new(metadata, positioningDoneEvent)` are used consistently across all tasks that reference them.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-11-round-recovery-hardening.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
