# Player Readiness Ownership — Design

**Date:** 2026-04-12
**Status:** Draft, pending user review
**Scope:** Server-side readiness consolidation. Client-side spectate controller is noted as a follow-up.

---

## 1. Problem

Today, the facts that determine whether a player is "ready to be put into a round" are scattered across four modules, none of which coordinate with each other:

- **`DataService`** stores profiles silently in a module-level table. It never fires an event when a profile is loaded; every consumer must pull via `profileFor()`, which returns `nil` on miss and logs a warn. No consumer can reliably wait for a profile.
- **`RoundService/executor.server.lua`** connects to `player.CharacterAdded` and waits up to 7 seconds (`CHARACTER_LOAD_TIMEOUT`) for `HumanoidRootPart` before kicking the player. This is the only timeout on character load anywhere in the system.
- **`WeaponDistributor/executor.server.lua`** connects to `player.CharacterAdded` and distributes tools if `_roundActive` is true. It pulls the loadout from `TeleportMetadataService.GetLoadout(player.UserId)`, which only works after `RoundSystem.new()` has run. This race is invisible when it wins and silently produces default loadouts when it loses.
- **`WeaponSystemState`** exposes `IsReady()` with a bounded wait — an explicit "ready"-exposing module, used once, in `RoundOrchestrator.enterAssigningTeams`.

Consequences, all observed or inferable from the current code:

1. `ProfileLoaded` races with character-loaded tool distribution — tools can be handed out before the profile is mounted, and `DataService` silently drops the mutation later.
2. Character-load failure kicks the player on a tight 7-second budget with no retry.
3. The "player-added → load character → write tools" flow has three independent timeouts in three files, none of which are composed.
4. `RoundSystem` owns state transitions but not the readiness facts the transitions depend on, so it can only react to them through polling or `pcall`-and-hope.
5. `WeaponSystemState` violates "one owner for readiness" outright.

## 2. Goal

`RoundSystem` is the sole owner of player readiness. It buffers facts pushed from producers, evaluates readiness when it needs to make a decision, and performs every action that depends on readiness itself. No module outside `RoundSystem/` ever queries "is this player ready" — the concept does not exist outside `RoundSystem`.

A readiness gate with a grace period runs before the first round of each match. For subsequent rounds, per-player late-teleport tolerates a short window after the round has already started. Players who fail readiness are skipped for the current round and re-evaluated on the next round boundary. All operations — distribution, positioning, skipping, state transitions — are idempotent.

## 3. Non-goals

- Client-side spectate camera is designed but not required for the server change to ship. Its implementation is follow-up work.
- No changes to the match protocol (teleport data, `RoundUpdate` broadcast shape, etc.) beyond the addition of `"Skipped"` as a valid `PlayerState.status` value.
- No changes to `KnifeService`/`GunService` weapon handling — they already gate on round state and player state correctly.
- No changes to `ProfileService` or `ProfileStore` semantics.

## 4. Architecture

### 4.1 The one-owner rule

`RoundSystem` is the sole decider of player readiness. No other module exposes or queries "ready". Producers push *facts* — single-purpose, atomic, named signals like `ProfileLoaded` — and `RoundSystem` buffers them into per-player records.

Three layers:

1. **Fact producers** (know nothing about readiness)
   - `DataService` fires `ServerEventBus:Fire("ProfileLoaded", player)` once its profile session is mounted. On failure paths, no event is fired; absence ≡ not loaded.
   - `TeleportMetadataService` is consulted synchronously by the orchestrator during `AssigningTeams`, which writes `LoadoutResolved` directly into the record.
   - Character-scoped facts (`CharacterLoaded`, `CharacterUsable`) are written by the orchestrator's `loadCharacterAndRecord` helper via a local `player.CharacterAdded:Once()` subscription scoped to that one call — not by a persistent executor listener. See §8.3.
   - `RoundService/executor.server.lua` only subscribes to `Players.PlayerAdded` / `Players.PlayerRemoving` (for record lifecycle), the `ServerEventBus("ProfileLoaded")` signal (for the profile fact), and the cosmetic `player.CharacterAdded` handler that positions the player in `InitialSpawnBox` during `WaitingForPlayers` — that handler does **not** write readiness facts.

2. **Readiness store** — new module `src/Server/RoundService/PlayerReadiness.lua`
   - Module-level `records: { [Player]: ReadinessRecord }`. Persists for the server lifetime; cleaned up explicitly on `PlayerRemoving`.
   - Pure data + idempotent writes. It writes facts, answers questions about records, and has a `ChangedSignal` for event-driven waits. It does not decide anything.
   - Only files under `src/Server/RoundService/` may `require` it. Enforced by convention (top-of-file comment).

3. **Readiness consumer** — `RoundSystem` (only `RoundSystem`)
   - `executor.server.lua` owns all fact-producing subscriptions.
   - `RoundOrchestrator` reads records when deciding state transitions and per-player positioning.
   - It calls `WeaponDistributor.distributeToPlayer(player, loadout)` directly as a pure action. `WeaponDistributor` no longer listens for anything.

### 4.2 Dependency diagram

```
DataService ──fire──► ServerEventBus ──────┐
                                           ▼
Roblox PlayerAdded ──────────► RoundSystem/executor ──► PlayerReadiness
Roblox CharacterAdded ────────┘        (writes facts)    (module-level
                                                          records)
                                           │
                                           ▼
                                   RoundOrchestrator
                                     (reads records,
                                      makes decisions)
                                           │
                                           ▼
                             WeaponDistributor.distributeToPlayer
                                  (stateless, idempotent)
```

### 4.3 Invariants enforced by convention

- Only `src/Server/RoundService/*` files `require` `PlayerReadiness`.
- No module outside `RoundSystem/` ever asks "is player X ready?"
- `PlayerReadiness` never calls back into `RoundSystem`. It is a dumb store.
- The set of required facts lives in one place: `Shared/Round/Configs.REQUIRED_FACTS`.

## 5. State machine

### 5.1 New state: `PreparingPlayers`

Inserted between `AssigningTeams` and `RoundActive`. Only the **first round** of each match passes through it; subsequent rounds go `RoundIntermission → RoundActive` directly, with per-player character-load waiting handled inline inside `enterRoundActive`.

### 5.2 `GAME_STATES` and `LEGAL_TRANSITIONS` (Shared/Round/Configs.lua)

```lua
GAME_STATES = {
    WaitingForPlayers = "WaitingForPlayers",
    AssigningTeams    = "AssigningTeams",
    PreparingPlayers  = "PreparingPlayers",   --// NEW
    RoundActive       = "RoundActive",
    RoundIntermission = "RoundIntermission",
    GameOver          = "GameOver",
    TeleportingOut    = "TeleportingOut",
    Aborted           = "Aborted",
}

LEGAL_TRANSITIONS = {
    WaitingForPlayers = { "AssigningTeams", "Aborted" },
    AssigningTeams    = { "PreparingPlayers", "Aborted" },   --// CHANGED
    PreparingPlayers  = { "RoundActive", "Aborted" },        --// NEW
    RoundActive       = { "RoundIntermission", "GameOver", "Aborted" },
    RoundIntermission = { "RoundActive", "GameOver", "Aborted" },
    GameOver          = { "TeleportingOut" },
    TeleportingOut    = {},
    Aborted           = { "TeleportingOut" },
}
```

### 5.3 `PLAYER_STATUSES`

```lua
PLAYER_STATUSES = {
    Alive        = "Alive",
    Dead         = "Dead",
    Disconnected = "Disconnected",
    Skipped      = "Skipped",   --// NEW
}
```

`TeamState.Recalculate` treats `Skipped` as not-alive. **The current code has an `else alive += 1` branch that would miscount `Skipped` as alive**, so it needs a change: the alive branch must become an explicit `state.status == Alive` check, with `Skipped` handled as a separate counter (or folded into the `Dead` counter — see §11.12).

### 5.4 New `Configs` entries

```lua
READINESS_GRACE_FIRST_ROUND = 20   --// PreparingPlayers global deadline
LATE_TELEPORT_GRACE         = 3    --// per-player wait after RoundActive entry (rounds 2+)
CHAR_FACT_WAIT_TIMEOUT      = 10   --// WaitForChild bound for HRP/Humanoid in loadCharacterAndRecord
POSITIONING_OUTER_TIMEOUT   = 6    --// safety backstop for RoundActive positioning tasks
DEFAULT_WALK_SPEED          = 16   --// restored by exitSkippedOrPosition; matches Roblox default

REQUIRED_FACTS = {
    "ProfileLoaded",
    "LoadoutResolved",
    "CharacterLoaded",
    "CharacterUsable",
}
```

### 5.5 Deleted `Configs` entries

- `CHARACTER_LOAD_TIMEOUT = 7` — superseded by `CHAR_FACT_WAIT_TIMEOUT` plus grace periods.

`KICK_REASONS.CharacterLoadTimeout` is retained for defensive kicks from unexpected edge paths, but is no longer triggered by the normal flow.

## 6. Round roster (authoritative player set)

`RoundSystem` introduces `_roundRoster: { Player }`, populated at the `AssigningTeams → PreparingPlayers` transition and never mutated in composition for the rest of the match. Every downstream read uses it.

```
AssigningTeams (enter):
    assign teams from _pendingPlayers + TeleportMetadataService
    _roundRoster      = { every player across both teams }
    _teamPlayers[1/2] = derived subsets of _roundRoster
    _playerStates[p]  = PlayerState.new(p, team) for p in _roundRoster
    record "LoadoutResolved" for each roster player (synchronous write from orchestrator)
    transition → PreparingPlayers
```

Downstream rules:

- `PreparingPlayers` checks readiness only for `_roundRoster`.
- `RoundActive` positions only players in `_roundRoster`.
- `TeamState`/`WinConditionEvaluator` operate on `_roundRoster` (via `_teamPlayers`/`_playerStates`).
- `_pendingPlayers` is cleared at the end of `AssigningTeams`. It only exists during `WaitingForPlayers`.

**Mid-round leave:** `UnregisterPlayer` no longer deletes `_playerStates[player]`. It sets `playerState.status = "Disconnected"`. The roster composition is preserved. Iterating `_playerStates` ≡ iterating the roster with current statuses.

**Match boundary:** the roster stays the same across intermissions (it's a match roster). It's torn down at `TeleportingOut`.

## 7. `PlayerReadiness` module contract

Location: `src/Server/RoundService/PlayerReadiness.lua`

### 7.1 `ReadinessRecord` shape

```lua
export type ReadinessRecord = {
    player: Player,
    facts: { [string]: boolean },   --// only ever contains keys for facts currently TRUE
    loadAttempt: number,            --// private; bumped by beginCharacterLoad
    createdAt: number,              --// os.clock() at creation; debugging only
}
```

`facts` only holds currently-true keys. Clearing a fact deletes the key, not sets it to `false`. Absence ≡ not-set, which makes `isComplete` a simple "all required keys present" check and eliminates stale-boolean ambiguity.

### 7.2 Public API

```lua
--// ---- Record lifecycle ----

PlayerReadiness.ensureRecord(player: Player): ReadinessRecord
--// Idempotent. Creates a fresh record if none exists; returns the existing one otherwise.

PlayerReadiness.destroyRecord(player: Player): ()
--// Idempotent. Removes the record. No-op if already gone.

PlayerReadiness.getRecord(player: Player): ReadinessRecord?
--// Read-only accessor. Does NOT create on miss.

--// ---- Session-scoped fact writes ----

PlayerReadiness.recordFact(player: Player, factName: string): ()
--// Idempotent. Sets record.facts[factName] = true and fires ChangedSignal once
--// (only if the fact wasn't already set — spam prevention).
--// If record doesn't exist, calls ensureRecord first.
--// If factName is not in REQUIRED_FACTS, warns and no-ops.

PlayerReadiness.clearFact(player: Player, factName: string): ()
--// Idempotent. Deletes record.facts[factName]. Fires ChangedSignal only if the fact
--// was previously set.

--// ---- Character-scoped fact writes (token-gated) ----

PlayerReadiness.beginCharacterLoad(player: Player): number
--// Increments record.loadAttempt and returns the NEW attempt number.
--// Clears CharacterLoaded and CharacterUsable from facts atomically.
--// Fires ChangedSignal once.
--// Caller MUST capture the return value synchronously and thread it into any
--// subsequent recordCharacterFact calls.
--// There is NO supported way to rediscover the token after this call — either
--// the caller still has it in a local variable, or they do not get to write
--// character facts.

PlayerReadiness.recordCharacterFact(player: Player, token: number, factName: string): ()
--// Writes a character-scoped fact only if `token` matches record.loadAttempt.
--// On stale token: drops the write, warns with token + current values.
--// On matching token: writes idempotently, fires ChangedSignal if newly set.
--// factName must be "CharacterLoaded" or "CharacterUsable".

--// ---- Reads ----

PlayerReadiness.isComplete(player: Player): boolean
--// True iff the record exists AND every fact in REQUIRED_FACTS is present.

PlayerReadiness.missingFacts(player: Player): { string }
--// Returns an array of required facts that are not present. Used for diagnostic
--// warns when a player is force-skipped.

--// ---- Waits (yielding) ----

PlayerReadiness.ChangedSignal: BindableEvent
--// Module-level signal fired on every record mutation. Not typically subscribed
--// to directly — use waitForChange / waitForComplete.

PlayerReadiness.waitForChange(timeout: number): ()
--// Yields until ChangedSignal fires or `timeout` elapses, whichever comes first.
--// Always returns within timeout + ε. Cleans up its connection and timer.

PlayerReadiness.waitForComplete(player: Player, timeout: number): boolean
--// Yields until isComplete(player) OR `timeout` elapses.
--// Returns true on completion, false on timeout.
--// Safe to call from multiple coroutines concurrently for the same player —
--// each caller has its own independent timeout budget and connection.
```

### 7.3 Idempotency guarantees

| Function | Idempotent? | Notes |
|---|---|---|
| `ensureRecord` | Yes | Second call returns existing; no mutation. |
| `destroyRecord` | Yes | No warn on missing. |
| `recordFact` | Yes | Setting an already-set fact is a no-op; no signal fire. |
| `clearFact` | Yes | Clearing an absent fact is a no-op; no signal fire. |
| `recordCharacterFact` | Yes | Stale token dropped; matching token idempotent. |
| `beginCharacterLoad` | Yes in outcome | Attempt number changes, but observable state (facts cleared, fresh window) is deterministic in shape. |
| `isComplete` / `missingFacts` | Yes | Pure reads. |
| `waitForComplete` | Deterministic given final state | Outcome is boolean; timing varies with record mutations. |

### 7.4 Producer wiring

| Fact | Producer | Wiring location | Write call |
|---|---|---|---|
| `ProfileLoaded` | `DataService` | End of `OnPlayerAdded`, after session mounted | `ServerEventBus:Fire("ProfileLoaded", player)` — executor subscribes and calls `recordFact` |
| `LoadoutResolved` | Orchestrator | `enterAssigningTeams`, after team resolved | Direct call: `PlayerReadiness.recordFact(player, "LoadoutResolved")` |
| `CharacterLoaded` | Orchestrator | Inside `loadCharacterAndRecord` after HRP+Humanoid found | `PlayerReadiness.recordCharacterFact(player, token, "CharacterLoaded")` |
| `CharacterUsable` | Orchestrator | Same call site | Same |

### 7.5 Write sites outside the module

Only two files ever call write functions on `PlayerReadiness`:

1. `src/Server/RoundService/executor.server.lua` — subscribes to `ServerEventBus`, `Players.PlayerAdded`, `Players.PlayerRemoving`. Translates each signal into a `PlayerReadiness` call.
2. `src/Server/RoundService/RoundOrchestrator.lua` — writes `LoadoutResolved` in `enterAssigningTeams`, calls `beginCharacterLoad` before every `player:LoadCharacter()` through `loadCharacterAndRecord`, calls `recordCharacterFact` after HRP+Humanoid wait succeeds.

### 7.6 Concurrent waiters

Multiple coroutines may call `waitForComplete(p, …)` concurrently for the same player. Each caller holds its own connection and timer. Terminal actions performed after a successful wait must be idempotent OR gated to run once per (player, round). See §8.4.

## 8. Round flow

### 8.1 `enterPreparingPlayers` — first-round global grace

```
--// Helper local to the orchestrator module.
allRosterReady(roster):
    for _, player in roster do
        if not PlayerReadiness.isComplete(player):
            return false
    return true

enterPreparingPlayers(system):
    local deadline = os.clock() + READINESS_GRACE_FIRST_ROUND

    --// Spawn per-player loads. Each task is bounded internally by
    --// loadCharacterAndRecord's own timeouts (CHAR_FACT_WAIT_TIMEOUT).
    --// Task failure writes no facts and does not itself call applySkipped —
    --// the post-wait cleanup loop below is the single site for force-skip.
    for _, player in system._roundRoster do
        task.spawn(function()
            loadCharacterAndRecord(player, READINESS_GRACE_FIRST_ROUND)
        end)

    --// Global event-driven wait — yields on signal OR timeout.
    while true:
        if allRosterReady(system._roundRoster): break
        local timeLeft = deadline - os.clock()
        if timeLeft <= 0: break
        PlayerReadiness.waitForChange(timeLeft)

    --// Deadline reached or all ready. Any incomplete player is force-skipped NOW,
    --// with physical side effects applied synchronously.
    for _, player in system._roundRoster do
        if not PlayerReadiness.isComplete(player):
            warn(`[Round] {player.Name} incomplete after PreparingPlayers grace: {table.concat(PlayerReadiness.missingFacts(player), ", ")}`)
            applySkipped(system, player, system._playerStates[player])

    system:_transition(Configs.GAME_STATES.RoundActive)
```

**Why force-skip lives only in the cleanup loop, not inside each task:** if each per-player task called `applySkipped` on its own timeout, two failure modes would compete — the task's internal timeout and the global deadline. A player whose task times out at 10 seconds would be force-skipped even though the global grace is 20 seconds and they could still become ready via another fact path (e.g., a profile that arrived at 15 seconds). Centralizing the skip decision at the cleanup loop means it fires exactly once, at the real deadline, against the authoritative final state of the record.

### 8.2 `enterRoundActive` — non-blocking, per-player late-teleport

`enterRoundActive` starts the round timer immediately and returns. Positioning runs in parallel. Late-teleport is genuinely late — the round is already live.

```
enterRoundActive(system):
    system._roundNumber += 1
    system._positioningPlayers = true   --// gates _checkWinCondition during positioning

    --// Round timer starts NOW, parallel to positioning.
    system._roundTimerTask = task.delay(ROUND_DURATION, roundTimeExpired)

    local remaining = 0
    local finalized = false
    local function finalize():
        if finalized: return
        finalized = true
        system._positioningPlayers = false
        system:_broadcastUpdate()
        system:_checkWinCondition()

    for _, player in system._roundRoster do
        local playerState = system._playerStates[player]
        if not playerState: continue
        if playerState.status == "Disconnected": continue
        if playerState.status == "Skipped": continue
            --// Round 1 force-skipped from PreparingPlayers. No late-teleport
            --// within the same round — they wait for the next intermission exit,
            --// which resets their status to Alive and re-runs this path.

        remaining += 1
        task.spawn(function()
            local ok, err = pcall(function()
                --// Fast path (round 1): facts already set by PreparingPlayers.
                --// Slow path (rounds 2+): intermission exit cleared char facts,
                --//                        so re-load with per-player LATE_TELEPORT_GRACE.
                if not PlayerReadiness.isComplete(player) then
                    local ready = loadCharacterAndRecord(player, LATE_TELEPORT_GRACE)
                    if not ready then
                        applySkipped(system, player, playerState)
                        return
                    end
                end
                exitSkippedOrPosition(
                    system,
                    player,
                    playerState,
                    getSpawnFor(system, playerState.team),
                    TeleportMetadataService.GetLoadout(player.UserId))
            end)
            if not ok then
                warn(`[Round] Positioning task errored for {player.Name}: {err}`)
                applySkipped(system, player, playerState)
            end
            remaining -= 1
            if remaining == 0: finalize()

    if remaining == 0: finalize()  --// edge case: nobody eligible

    --// Backstop — NOT a gate. Parallel to positioning and the round timer.
    task.delay(POSITIONING_OUTER_TIMEOUT, function()
        if finalized: return
        warn("[Round] Positioning outer safety timer fired")
        for _, player in system._roundRoster do
            local state = system._playerStates[player]
            if state and state.status not in {Alive, Skipped, Disconnected}:
                applySkipped(system, player, state)
        finalize()

    --// enterRoundActive returns HERE.
```

Round-timer scheduling is not gated by positioning. `finalize` runs on the tail of the last completing per-player task (or the safety backstop, in pathological cases). `_positioningPlayers` is true for the window between `enterRoundActive` and `finalize`, during which `_checkWinCondition` early-returns — preventing premature round-end from kills that happen mid-positioning.

**Skipped-in-round-1 semantics:** a player force-skipped during `PreparingPlayers` enters `enterRoundActive` already in `status = "Skipped"`. The positioning loop above `continue`s past them — no per-player task is spawned, they are not counted in `remaining`, and they are not given a second chance within the same round. Their sidelined physical state (set by `applySkipped` earlier) persists through round 1. At the next `RoundIntermission` exit, their status resets to `"Alive"` (§8.6) and the rounds-2+ slow path gives them a fresh 3-second attempt.

### 8.3 `loadCharacterAndRecord` — the only character-load driver

```
loadCharacterAndRecord(player, timeout):
    local token = PlayerReadiness.beginCharacterLoad(player)   --// captured synchronously

    local characterResult
    local characterSignal = Instance.new("BindableEvent")
    local conn = player.CharacterAdded:Once(function(c)
        characterResult = c
        characterSignal:Fire()
    end)

    player:LoadCharacter()

    --// Event-driven wait: yields on character arrival OR timeout.
    if not characterResult:
        local timer = task.delay(timeout, function() characterSignal:Fire() end)
        characterSignal.Event:Wait()
        task.cancel(timer)
    characterSignal:Destroy()

    if not characterResult:
        conn:Disconnect()   --// defensive; :Once auto-disconnects on fire but not on timeout
        return false

    --// Bounded wait for HRP + Humanoid on the specific character.
    local deadline = os.clock() + CHAR_FACT_WAIT_TIMEOUT
    local hrp      = characterResult:WaitForChild("HumanoidRootPart", CHAR_FACT_WAIT_TIMEOUT)
    local humanoid = characterResult:WaitForChild("Humanoid", CHAR_FACT_WAIT_TIMEOUT)
    if not hrp or not humanoid: return false

    --// Write facts with the captured token. Store-level gate handles any race.
    PlayerReadiness.recordCharacterFact(player, token, "CharacterLoaded")
    PlayerReadiness.recordCharacterFact(player, token, "CharacterUsable")
    return true
```

Token capture rule: `token` is the return value of `beginCharacterLoad`, bound to a local variable in the same coroutine frame. It is never re-read from the store. The store-level check in `recordCharacterFact` is the final safety net.

This function is the **sole** caller of `player:LoadCharacter()` for round-scoped loads. Called by `enterPreparingPlayers` (once per roster player, in parallel) and `enterRoundActive` (once per roster player, in parallel). The initial waiting-area `LoadCharacter()` in `setupPlayer` is the only exception — it is cosmetic and does not interact with `PlayerReadiness` at all.

### 8.4 `applySkipped` — immediate, synchronous, idempotent

`Skipped` is applied immediately at the moment of the decision. All side effects run synchronously in the same function call before it returns. There is no "handled next tick" deferral.

```
applySkipped(system, player, playerState):
    if playerState.status == "Skipped": return    --// idempotent

    playerState.status = "Skipped"

    clearBackpack(player)                          --// no prior tools
    local character = player.Character
    if character:
        local hrp      = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if hrp:
            hrp.CFrame    = pickInitialSpawnCFrame()   --// out of active spawn state
            hrp.Anchored  = true                       --// can't wander
        if humanoid:
            humanoid.WalkSpeed = 0
        if not character:FindFirstChildOfClass("ForceField"):
            Instance.new("ForceField", character)      --// damage immunity
    else:
        warn(`[Round] applySkipped: {player.Name} has no character; physical side effects deferred until next character load`)

    system:_broadcastUpdate()   --// clients see new status atomically with the physical change
```

**Signature note:** `applySkipped` takes `system` as its first parameter explicitly (not closed over) so it can be called from any helper inside the orchestrator module without scope fragility. The same convention applies to `exitSkippedOrPosition` — see §8.5.

**Invariant:** between `status = "Skipped"` and the return of `applySkipped`, the player cannot influence combat, cannot hold prior tools, and cannot remain in an old active spawn state.

### 8.5 `exitSkippedOrPosition` — idempotent gate per (player, round)

```
exitSkippedOrPosition(system, player, playerState, spawnPart, loadout):
    if playerState.positionedThisRound: return   --// run-once gate per round
    playerState.positionedThisRound = true

    playerState.status = "Alive"                  --// transition out of Skipped if applicable

    local character = player.Character
    if not character:
        warn(`[Round] exitSkippedOrPosition: {player.Name} has no character; cannot position`)
        return

    local hrp      = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if hrp:
        hrp.Anchored = false
        hrp.CFrame   = spawnPart.CFrame + Vector3.new(0, 3, 0)
    if humanoid:
        humanoid.WalkSpeed = Configs.DEFAULT_WALK_SPEED

    --// Remove any lingering ForceField from a prior Skipped state.
    for _, child in character:GetChildren():
        if child:IsA("ForceField"): child:Destroy()

    --// Idempotent distribution — checks backpack + character for each tool.
    WeaponDistributor.distributeToPlayer(player, loadout.knifeName, loadout.gunName)
```

The `positionedThisRound` flag is a `PlayerState` field, reset to `false` at `RoundIntermission` exit (and at `AssigningTeams` for round 1). The check-then-set happens inside a single coroutine frame with no intervening yield, so it is effectively atomic.

### 8.6 `enterRoundIntermission` — exit cleanup

On entry: locks all `Alive` player states (existing behavior).

On exit (the `task.delay` callback after `ROUND_INTERMISSION_DURATION`):

- For each roster player:
  - `playerState:Unlock()` (existing)
  - `playerState:Reset()` (existing — clears per-round stats)
  - `playerState.positionedThisRound = false`
  - If `status == "Dead"` → set to `"Alive"` (existing)
  - If `status == "Skipped"` → set to `"Alive"` (re-eligible for next round)
  - If `status == "Disconnected"` → leave alone
- For each roster player, clear `CharacterLoaded` and `CharacterUsable` from the readiness record (forces re-evaluation on next `RoundActive` entry).

## 9. `Skipped` real-world contract

### 9.1 Physical state (server)

- Character exists in the match workspace.
- `HumanoidRootPart.CFrame` is set inside `workspace.InitialSpawnBox`, using the same randomized-box logic that `WaitingForPlayers` already uses.
- `HumanoidRootPart.Anchored = true`.
- `Humanoid.WalkSpeed = 0`.
- A `ForceField` parented to the character, visible.
- Backpack is empty.
- `player.Team` is preserved.

### 9.2 Round state (server)

- `PlayerState.status = "Skipped"`.
- `PlayerState.stats` preserved across rounds.
- `TeamState.Recalculate` treats `Skipped` as not-alive (same as `Dead`).
- `WinConditionEvaluator` unchanged — it sees a correct alive count.
- `RoundSystem:OnPlayerDied` early-returns if `playerState.status == "Skipped"` (defensive; ForceField + Anchored should make death impossible).
- `RoundUpdate` broadcast carries `status` → clients see `Skipped` automatically.

### 9.3 Spectate affordance (client)

Implemented via a client controller that reads `PlayerState.status` from the existing `RoundUpdate` broadcast. No new remotes. No server cooperation beyond the existing broadcast. When own `status == "Skipped"`, camera follows an `Alive` teammate (preferring same team). Transitioning `Skipped → Alive` snaps the camera back to own character.

This is follow-up work. The server-side consolidation is correct and shippable without it.

### 9.4 Re-eligibility cadence

- **Rounds 2+ late-join:** 3-second `LATE_TELEPORT_GRACE` window after `RoundActive` entry. The per-player task in `enterRoundActive` watches for readiness; if it completes within 3 seconds, `exitSkippedOrPosition` runs and the player late-joins the round.
- **Intermission exit:** `RoundIntermission → RoundActive` resets skipped players' `status` to `"Alive"`. The next `RoundActive` per-player task re-evaluates them through the same flow.

### 9.5 Edge case — entire team skipped

`WinConditionEvaluator` sees one team with 0 alive → other team wins trivially → normal `RoundIntermission` → next round retry. Degraded but correct round.

## 10. Timeout audit

Every yielding call in the readiness path must be bounded, and every roster player must terminate in `Alive`, `Skipped`, or `Disconnected`.

| Wait site | Bound | Termination |
|---|---|---|
| `PreparingPlayers` global wait | `READINESS_GRACE_FIRST_ROUND = 20` | Deadline expiry triggers `applySkipped` for incomplete players. |
| Per-player wait in `RoundActive` (via `loadCharacterAndRecord`) | `LATE_TELEPORT_GRACE = 3` | Timeout returns `false`; task calls `applySkipped`. |
| `loadCharacterAndRecord` internal — `characterSignal:Wait` | `timeout` arg | Signal fires on character arrival OR timeout. |
| `loadCharacterAndRecord` internal — `WaitForChild("HumanoidRootPart")` | `CHAR_FACT_WAIT_TIMEOUT = 10` | Returns `nil` on timeout; task returns `false`. |
| `loadCharacterAndRecord` internal — `WaitForChild("Humanoid")` | `CHAR_FACT_WAIT_TIMEOUT = 10` | Same. |
| `PlayerReadiness.waitForChange` | caller-supplied | Binds signal + `task.delay`, cleans up on return. |
| `PlayerReadiness.waitForComplete` | caller-supplied | Loop exits on `isComplete` true OR `timeLeft <= 0`. |
| `enterRoundActive` safety backstop | `POSITIONING_OUTER_TIMEOUT = 6` | Force-finalizes if `finalize` hasn't run yet. |
| Round timer, intermission, game-over delays | Fixed `task.delay` | Terminate on schedule. |
| `TeleportUtility.teleportPlayersWithRetry` | Existing retry cap | Bounded. |

### 10.1 Script-load wait elimination

Current `executor.server.lua` has:
```lua
local positioningDoneEvent =
    ServerStorage:WaitForChild("RoundEvents"):WaitForChild("PositioningDone")
```
This hangs forever if the event is missing. **Removed.** `RoundSystem` no longer uses an external `BindableEvent` for positioning — the previous "done event" was a counter-based join that this design replaces with per-player finalization.

### 10.2 Per-player task error guard

Every per-player task in `enterRoundActive`'s positioning loop is wrapped in `pcall`. On error, `applySkipped` runs and `remaining` is still decremented. No task can leave `remaining` in a stuck state.

## 11. Module-by-module changes

### 11.1 New files

- **`src/Server/RoundService/PlayerReadiness.lua`** — full module per §7.

### 11.2 `src/Shared/Round/Types.lua`

Add:
```lua
export type PlayerStatus = "Alive" | "Dead" | "Disconnected" | "Skipped"
export type ReadinessFact = "ProfileLoaded" | "LoadoutResolved" | "CharacterLoaded" | "CharacterUsable"
```

### 11.3 `src/Shared/Round/Configs.lua`

Additions per §5.4. Modifications per §5.2 and §5.3. Deletion per §5.5.

### 11.4 `src/Server/DataService/init.lua`

At the end of `OnPlayerAdded`, after `Profiles[player] = profile`:

```lua
Profiles[player] = profile
debugPrint(DEBUG, `[DataService] Profile stored for {player.Name}`)
ServerEventBus:Fire("ProfileLoaded", player)   --// NEW
```

Add `local ServerEventBus = require(ServerScriptService.ServerEventBus)` at the top. On failure paths, no event is fired.

No other changes. No `IsLoaded` query added. No signal exposed. Single-line producer.

### 11.5 `src/Server/WeaponDistributor/executor.server.lua`

Simplified drastically. Validation happens at require-time. On failure, the module errors out at load time (server refuses to start — loud and immediate):

```lua
local validationOk, problems, knives, guns = validateWeapons()
if not validationOk then
    warn("[WeaponDistributor] CRITICAL — weapon validation failed:")
    for _, msg in problems do warn(`  - {msg}`) end
    error("[WeaponDistributor] cannot initialize")
end
local initOk = WeaponDistributor.init(knives, guns)
if not initOk then error("[WeaponDistributor] init failed") end

--// No CharacterAdded listeners. No _roundActive flag. No ServerEventBus wiring.
--// RoundSystem calls WeaponDistributor.distributeToPlayer directly.
```

### 11.6 `src/Server/WeaponDistributor/init.lua`

`distributeToPlayer` becomes fully idempotent:

```lua
function WeaponDistributor.distributeToPlayer(player: Player, knifeName: string?, gunName: string?)
    local character = player.Character
    if not character then
        warn(`[WeaponDistributor] {player.Name} has no character`)
        return
    end
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then
        warn(`[WeaponDistributor] {player.Name} has no backpack`)
        return
    end

    local function giveIfAbsent(toolName: string?, templates: { [string]: Tool })
        if not toolName then return end
        if backpack:FindFirstChild(toolName) then return end
        if character:FindFirstChild(toolName) then return end
        local template = templates[toolName]
        if not template then
            warn(`[WeaponDistributor] no template for "{toolName}"`)
            return
        end
        local clone = template:Clone()
        clone.Parent = backpack
    end

    giveIfAbsent(knifeName or Configs.DEFAULT_LOADOUT.knifeName, _knifeTemplates)
    giveIfAbsent(gunName or Configs.DEFAULT_LOADOUT.gunName, _gunTemplates)
end
```

Calling it twice with the same inputs produces the same backpack state.

### 11.7 `src/Server/WeaponSystemState/`

**Deleted.** Its `IsReady()` was the only "expose ready to other modules" violation in the codebase.

### 11.8 `src/Server/RoundService/executor.server.lua`

- Add `require` of `PlayerReadiness`.
- Subscribe `ServerEventBus:Connect("ProfileLoaded", function(player) PlayerReadiness.recordFact(player, "ProfileLoaded") end)` at script load.
- In `setupPlayer`: call `PlayerReadiness.ensureRecord(player)` first.
- Remove the `ServerStorage.RoundEvents.PositioningDone` WaitForChild and the `positioningDoneEvent` parameter to `RoundService.new`.
- Initial waiting-area `player:LoadCharacter()` and its `CharacterAdded` handler (for `InitialSpawnBox` positioning and `Humanoid.Died` wiring) are **unchanged** — they are cosmetic and do not touch readiness facts.
- `Players.PlayerRemoving`: also call `PlayerReadiness.destroyRecord(player)`.

### 11.9 `src/Server/RoundService/init.lua`

- `RoundSystem.new(metadata)` drops the `positioningDoneEvent` parameter.
- Add `self._roundRoster: { Player } = {}`.
- `UnregisterPlayer` no longer deletes `_playerStates[player]`. It sets `playerState.status = "Disconnected"` and leaves the entry in place. It does **not** call `PlayerReadiness.destroyRecord` — that is the executor's responsibility (see §11.8), since the executor already owns the `Players.PlayerRemoving` subscription and the record lifecycle belongs there.
- `RegisterPlayer` unchanged.
- `OnPlayerDied` adds an early-return guard: if `playerState.status == "Skipped"`, warn and return. Skipped players should not reach this path in normal operation (ForceField + Anchored), but the guard is defensive against unexpected engine behavior.

### 11.10 `src/Server/RoundService/RoundOrchestrator.lua`

- Delete the `require(ServerScriptService.WeaponSystemState)` and the `IsReady` check in `enterAssigningTeams`.
- `enterAssigningTeams`:
  - After team assignment, populate `system._roundRoster` from both team lists.
  - For each roster player, call `PlayerReadiness.recordFact(player, "LoadoutResolved")`.
  - Transition to `PreparingPlayers` (not `RoundActive`).
- Add `enterPreparingPlayers` per §8.1.
- Rewrite `enterRoundActive` per §8.2.
- Update `enterRoundIntermission` exit callback per §8.6 (clear character facts, reset `positionedThisRound`, transition `Skipped → Alive`).
- Add module-local helpers:
  - `loadCharacterAndRecord(player, timeout) -> boolean` — per §8.3.
  - `applySkipped(system, player, playerState)` — per §8.4.
  - `exitSkippedOrPosition(system, player, playerState, spawnPart, loadout)` — per §8.5.
  - `allRosterReady(roster) -> boolean` — simple loop over roster calling `PlayerReadiness.isComplete`, per §8.1.
  - `getSpawnFor(system, teamNum) -> BasePart` — rotates spawn parts the same way the existing `getSpawnAssignment` does. For each positioning call, hands out the next spawn part in the team's rotation. Implementation: pre-compute `spawnGroups` once per round entry and use a per-team index counter. Replaces the inline spawn-assignment logic currently embedded in `loadAndPositionPlayers`.

### 11.11 `src/Server/RoundService/PlayerState.lua`

- New field: `positionedThisRound: boolean` (default `false`).
- Contract update: `status` may now be `"Skipped"`.
- `Reset()` clears `positionedThisRound` in addition to existing behavior.

### 11.12 `src/Server/RoundService/TeamState.lua`

**`Recalculate()` needs a change.** The current implementation is `if Disconnected elseif Dead else alive += 1` — the `else` catches every non-Dead, non-Disconnected status, including `Skipped`. Fix: add an explicit `Skipped` branch and make the alive increment explicitly require `status == Alive`.

```lua
if state.status == Configs.PLAYER_STATUSES.Disconnected then
    disconnected += 1
elseif state.status == Configs.PLAYER_STATUSES.Dead then
    dead += 1
elseif state.status == Configs.PLAYER_STATUSES.Skipped then
    skipped += 1
elseif state.status == Configs.PLAYER_STATUSES.Alive then
    alive += 1
else
    warn(`[TeamState] Unknown status: {state.status}`)
end
```

The `Recalculate` snapshot also gains a `skippedPlayers: number` field. `totalPlayerCount` becomes `alive + dead + skipped` so `HasFullDisconnect()` doesn't lie about an all-skipped team.

### 11.13 `src/Server/KnifeService/` and `src/Server/GunService/`

**Zero changes.** Their existing gates (round state, player state, profile presence) correctly handle `Skipped` players as "not in the round".

### 11.14 Client-side — `SpectateController` (follow-up)

Per §9.3. Not blocking for the server change to ship.

## 12. Error handling matrix

| Scenario | Behavior |
|---|---|
| Profile load fails in `DataService` | Existing: player kicked. No `ProfileLoaded` event fired. They're force-skipped in grace, but that's moot because they're already kicked. |
| `LoadCharacter` yields forever | `loadCharacterAndRecord` times out, returns `false`, task calls `applySkipped`. |
| `CharacterAdded` never fires | `:Once` never fires, `characterResult` stays nil, timeout path taken, force-skipped. |
| HRP or Humanoid never appears | `WaitForChild` returns nil after `CHAR_FACT_WAIT_TIMEOUT`, `loadCharacterAndRecord` returns `false`, force-skipped. |
| Stale `CharacterAdded` for a prior load | Token gate in `recordCharacterFact` drops the write with a warn. |
| `WeaponDistributor` template missing | `distributeToPlayer` warns and skips that specific tool; player is positioned with partial loadout. Non-fatal. |
| `TeleportMetadataService` missing loadout | Orchestrator logs a warn and falls back to `Configs.DEFAULT_LOADOUT`. `LoadoutResolved` is still recorded (the player is playable with default weapons). A missing loadout is a data-entry bug, not a fatal readiness failure. |
| Weapon validation fails at server start | `WeaponDistributor/executor.server.lua` errors at module load → server refuses to start. |
| Per-player positioning task raises an error | `pcall` wrapper catches it, calls `applySkipped`, decrements `remaining`. |
| Entire team force-skipped | `WinConditionEvaluator` → other team wins trivially → intermission → next round retry. |
| Player disconnects mid-grace | `UnregisterPlayer` sets status to `"Disconnected"`. `destroyRecord` runs. Per-player task's `loadCharacterAndRecord` times out (no character arrives), task exits cleanly, `remaining` decremented. |
| Player disconnects mid-round after positioning | Existing behavior: `UnregisterPlayer` sets status. Win condition re-evaluated. |

## 13. Testing notes (for the implementation-plan phase)

Not part of this design, but captured here for `writing-plans`:

- **`PlayerReadiness`** is a pure module — unit-testable with fake Player tables and direct API calls. Tests for: `ensureRecord` idempotency, `recordFact` absence-vs-present semantics, `beginCharacterLoad` token monotonicity, `recordCharacterFact` stale-token drop, `waitForComplete` immediate completion, `waitForComplete` timeout, concurrent callers sharing a record.
- **`applySkipped`** and **`exitSkippedOrPosition`** are testable with fake `PlayerState` + fake Character.
- **`loadCharacterAndRecord`** requires a real `player:LoadCharacter` — integration test via `mcp__robloxstudio__execute_luau` in an open session.
- **Grace flows** — integration tests: (1) happy path first round, (2) first round with one player's profile delayed artificially, (3) rounds 2+ with one player's character load delayed, (4) entire team force-skipped, (5) disconnect during grace.

## 14. Summary

Readiness becomes single-owner. Producers push facts. The round system consumes them. First round has a global grace; subsequent rounds have per-player late-teleport after the round has already started. Failure is always terminal (Alive, Skipped, or Disconnected — never "stuck") and always idempotent. All side effects of being `Skipped` apply synchronously at the moment of the decision. Character-scoped facts are bound to a captured load token so stale async writes cannot corrupt a fresh attempt. `WeaponSystemState` is deleted; `WeaponDistributor` becomes a stateless, idempotent action module.
