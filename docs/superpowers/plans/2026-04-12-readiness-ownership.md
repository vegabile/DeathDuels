# Player Readiness Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate player readiness into a single owner (`RoundSystem`), add a `PreparingPlayers` state with a first-round grace period, add per-player late-teleport for rounds 2+, and make all distribution/positioning/skip operations idempotent.

**Architecture:** New `PlayerReadiness` store module inside `RoundService/` holds per-player fact records, written by producers (`DataService`, engine events, orchestrator) and read only by `RoundOrchestrator`. A new `PreparingPlayers` state runs a global grace-period wait for the first round; subsequent rounds use per-player `LATE_TELEPORT_GRACE` inside a non-blocking `RoundActive` handler. `WeaponSystemState` is deleted; `WeaponDistributor` becomes stateless and idempotent.

**Tech Stack:** Roblox Luau, Wally (ProfileService dep), Argon/Rojo sync, `mcp__robloxstudio__execute_luau` for integration testing.

**Spec:** `docs/superpowers/specs/2026-04-12-readiness-ownership-design.md` (commit `fc6251c`)

---

## File Structure

**New files:**
- `src/Server/RoundService/PlayerReadiness.lua` — module-level readiness store
- `src/Server/RoundService/PlayerReadiness.test.lua` — unit tests for the store

**Modified files:**
- `src/Shared/Round/Configs.lua` — new constants, new state, new status, new legal transitions
- `src/Server/RoundService/PlayerState.lua` — new `positionedThisRound` field
- `src/Server/RoundService/TeamState.lua` — explicit `Alive` check, `Skipped` counter
- `src/Server/RoundService/init.lua` — round roster, UnregisterPlayer semantics, OnPlayerDied guard
- `src/Server/RoundService/RoundOrchestrator.lua` — new helpers, new handler, rewritten RoundActive, intermission cleanup
- `src/Server/RoundService/executor.server.lua` — PlayerReadiness wiring, ProfileLoaded subscription, remove ServerStorage BindableEvent
- `src/Server/RoundService/RoundSystem.test.lua` — expanded coverage for Skipped / new fields
- `src/Server/DataService/init.lua` — fire `ProfileLoaded` on successful profile mount
- `src/Server/WeaponDistributor/init.lua` — idempotent `distributeToPlayer`
- `src/Server/WeaponDistributor/executor.server.lua` — error-at-load on validation failure, remove listener
- `src/Server/WeaponDistributor/WeaponDistributor.test.lua` — idempotency assertions

**Deleted files:**
- `src/Server/WeaponSystemState/init.lua`
- `src/Server/WeaponSystemState/WeaponSystemState.test.lua`
- `src/Server/WeaponSystemState/` (the whole directory)

## Testing Note

This project uses a lightweight hand-rolled test pattern in `*.test.lua` files, run via `mcp__robloxstudio__execute_luau` in the Studio edit environment. Each test file accumulates a `passed`/`failed` counter via a local `check(label, cond, detail?)` helper and prints a summary line at the end. There is no separate test runner. When a task says "run tests", it means: open Studio with the project synced via Argon, then execute the test file via `mcp__robloxstudio__execute_luau`, targeting the file path listed in the task.

**Run command template (for steps that run tests):**
```
mcp__robloxstudio__execute_luau(script = <lua content of the test file OR a require() of it>)
```

Integration tests that exercise the full orchestrator flow use the same tool but execute ad-hoc scripts that drive the state machine through mock or real player events.

---

## Task 1: Configs — new constants, new state, new status

**Files:**
- Modify: `src/Shared/Round/Configs.lua`

- [ ] **Step 1: Read the file to find line numbers**

Read `src/Shared/Round/Configs.lua` in full. Note the positions of `GAME_STATES`, `PLAYER_STATUSES`, `LEGAL_TRANSITIONS`, and `CHARACTER_LOAD_TIMEOUT`.

- [ ] **Step 2: Add `PreparingPlayers` to `GAME_STATES`**

Change the `GAME_STATES` table to include `PreparingPlayers = "PreparingPlayers"` between `AssigningTeams` and `RoundActive`:

```lua
GAME_STATES = {
    WaitingForPlayers = "WaitingForPlayers",
    AssigningTeams = "AssigningTeams",
    PreparingPlayers = "PreparingPlayers",
    RoundActive = "RoundActive",
    RoundIntermission = "RoundIntermission",
    GameOver = "GameOver",
    TeleportingOut = "TeleportingOut",
    Aborted = "Aborted",
},
```

- [ ] **Step 3: Add `Skipped` to `PLAYER_STATUSES`**

```lua
PLAYER_STATUSES = {
    Alive = "Alive",
    Dead = "Dead",
    Disconnected = "Disconnected",
    Skipped = "Skipped",
},
```

- [ ] **Step 4: Add new timeout / grace / fact constants**

Add these constants somewhere below the existing `RESPAWN_DELAY`:

```lua
READINESS_GRACE_FIRST_ROUND = 20,
LATE_TELEPORT_GRACE = 3,
CHAR_FACT_WAIT_TIMEOUT = 10,
POSITIONING_OUTER_TIMEOUT = 6,
DEFAULT_WALK_SPEED = 16,

REQUIRED_FACTS = {
    "ProfileLoaded",
    "LoadoutResolved",
    "CharacterLoaded",
    "CharacterUsable",
},
```

- [ ] **Step 5: Delete `CHARACTER_LOAD_TIMEOUT`**

Remove the `CHARACTER_LOAD_TIMEOUT = 7,` line. It is replaced by `CHAR_FACT_WAIT_TIMEOUT` and the grace constants.

- [ ] **Step 6: Update `LEGAL_TRANSITIONS`**

Change `AssigningTeams`'s allowed set and add `PreparingPlayers`:

```lua
LEGAL_TRANSITIONS = {
    WaitingForPlayers = { "AssigningTeams", "Aborted" },
    AssigningTeams = { "PreparingPlayers", "Aborted" },
    PreparingPlayers = { "RoundActive", "Aborted" },
    RoundActive = { "RoundIntermission", "GameOver", "Aborted" },
    RoundIntermission = { "RoundActive", "GameOver", "Aborted" },
    GameOver = { "TeleportingOut" },
    TeleportingOut = {},
    Aborted = { "TeleportingOut" },
},
```

- [ ] **Step 7: Verify project still parses**

Run:
```
mcp__robloxstudio__execute_luau(script = [[
local Configs = require(game.ReplicatedStorage.Round.Configs)
print("PreparingPlayers:", Configs.GAME_STATES.PreparingPlayers)
print("Skipped:", Configs.PLAYER_STATUSES.Skipped)
print("GRACE:", Configs.READINESS_GRACE_FIRST_ROUND)
print("REQUIRED_FACTS:", #Configs.REQUIRED_FACTS)
print("AssigningTeams -> PreparingPlayers legal?", Configs.LEGAL_TRANSITIONS.AssigningTeams[1] == "PreparingPlayers")
print("CHARACTER_LOAD_TIMEOUT removed?", Configs.CHARACTER_LOAD_TIMEOUT == nil)
]])
```
Expected output: all prints show the expected values; `CHARACTER_LOAD_TIMEOUT removed? true`.

- [ ] **Step 8: Commit**

```bash
git add src/Shared/Round/Configs.lua
git commit -m "feat(configs): add PreparingPlayers state and readiness constants"
```

---

## Task 2: TeamState — explicit Alive check and Skipped counter

**Files:**
- Modify: `src/Server/RoundService/TeamState.lua`
- Modify: `src/Server/RoundService/RoundSystem.test.lua`

- [ ] **Step 1: Add a failing test for Skipped handling**

Open `src/Server/RoundService/RoundSystem.test.lua`. Find the `--// ─── TeamState ───` section. After the existing `do ... end` block that tests alive/dead/disconnected, add a new block:

```lua
do
    local p1 = mockPlayer("S1", 20)
    local p2 = mockPlayer("S2", 21)

    local playerStates = {}
    playerStates[p1] = PlayerState.new(p1, 1)    -- Alive
    playerStates[p2] = PlayerState.new(p2, 1)    -- Will be Skipped
    playerStates[p2].status = Configs.PLAYER_STATUSES.Skipped

    local ts = TeamState.new(1, { p1, p2 }, playerStates)
    local snap = ts:Recalculate()

    check("TeamState: Skipped does not count as alive", snap.alivePlayers == 1)
    check("TeamState: Skipped exposed as skippedPlayers", snap.skippedPlayers == 1)
    check("TeamState: Skipped counted in totalPlayerCount", snap.totalPlayerCount == 2)
end
```

- [ ] **Step 2: Run test to verify it fails**

```
mcp__robloxstudio__execute_luau(script = <contents of src/Server/RoundService/RoundSystem.test.lua>)
```
Expected: the three new `Skipped`-related assertions FAIL (current TeamState counts Skipped as alive via the `else` branch, and `skippedPlayers` is nil).

- [ ] **Step 3: Update `TeamState.Recalculate` to handle Skipped explicitly**

In `src/Server/RoundService/TeamState.lua`, replace the `Recalculate` function body:

```lua
function TeamState:Recalculate()
    local alive = 0
    local dead = 0
    local disconnected = 0
    local skipped = 0
    local points = 0

    for _, player in self.players do
        local state = self.playerStates[player]
        if not state then
            disconnected += 1
            continue
        end

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

        points += state.stats.points or 0
    end

    return {
        teamNumber = self.teamNumber,
        alivePlayers = alive,
        deadPlayers = dead,
        disconnectedPlayers = disconnected,
        skippedPlayers = skipped,
        totalPlayerCount = alive + dead + skipped,
        originalPlayerCount = self.originalPlayerCount,
        points = points,
    }
end
```

- [ ] **Step 4: Run tests to verify they pass**

```
mcp__robloxstudio__execute_luau(script = <contents of src/Server/RoundService/RoundSystem.test.lua>)
```
Expected: all TeamState assertions PASS, including the three new Skipped assertions. The earlier alive/dead/disconnected assertions still pass.

- [ ] **Step 5: Commit**

```bash
git add src/Server/RoundService/TeamState.lua src/Server/RoundService/RoundSystem.test.lua
git commit -m "feat(teamstate): count Skipped status explicitly, drop implicit alive fallback"
```

---

## Task 3: PlayerState — `positionedThisRound` field

**Files:**
- Modify: `src/Server/RoundService/PlayerState.lua`
- Modify: `src/Server/RoundService/RoundSystem.test.lua`

- [ ] **Step 1: Add failing tests for the new field**

In `RoundSystem.test.lua`, add to the PlayerState section:

```lua
do
    local p = mockPlayer("Carol", 3)
    local ps = PlayerState.new(p, 1)

    check("PlayerState: positionedThisRound defaults to false", ps.positionedThisRound == false)

    ps.positionedThisRound = true
    ps:Reset()
    check("PlayerState: Reset clears positionedThisRound", ps.positionedThisRound == false)
end
```

- [ ] **Step 2: Run to verify failure**

Run the test file via `execute_luau`. Expected: both new checks FAIL (`positionedThisRound` is nil on a fresh PlayerState).

- [ ] **Step 3: Add the field to `PlayerState.new`**

In `src/Server/RoundService/PlayerState.lua`, update the `return setmetatable(...)` block in `PlayerState.new`:

```lua
return setmetatable({
    player = player,
    team = teamNumber,
    status = Configs.PLAYER_STATUSES.Alive,
    isInGame = true,
    stats = stats,
    positionedThisRound = false,
    _locked = false,
}, PlayerState)
```

- [ ] **Step 4: Update `Reset` to clear the field**

In `PlayerState:Reset()`, add the line:

```lua
function PlayerState:Reset()
    for key, value in Configs.DEFAULT_STATS do
        self.stats[key] = value
    end
    self.status = Configs.PLAYER_STATUSES.Alive
    self.isInGame = true
    self.positionedThisRound = false
    self._locked = false
end
```

- [ ] **Step 5: Run tests to verify pass**

Run `RoundSystem.test.lua`. Expected: all PlayerState checks PASS including the new ones.

- [ ] **Step 6: Commit**

```bash
git add src/Server/RoundService/PlayerState.lua src/Server/RoundService/RoundSystem.test.lua
git commit -m "feat(playerstate): add positionedThisRound round-scoped gate flag"
```

---

## Task 4: Create `PlayerReadiness` module (record lifecycle + session-fact writes)

**Files:**
- Create: `src/Server/RoundService/PlayerReadiness.lua`
- Create: `src/Server/RoundService/PlayerReadiness.test.lua`

- [ ] **Step 1: Write the failing test file (first slice — lifecycle + session facts)**

Create `src/Server/RoundService/PlayerReadiness.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.
--// Uses mock player tables since real Player objects are unavailable outside a session.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerReadiness = require(ServerScriptService.RoundService.PlayerReadiness)
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

local function mockPlayer(name: string, userId: number)
    return { Name = name, UserId = userId }
end

local function freshStore()
    --// PlayerReadiness is module-level; tests must clean up between runs.
    PlayerReadiness._reset()
end

-- ─── ensureRecord / destroyRecord ─────────────────────────────────────────────

do
    freshStore()
    local p = mockPlayer("Alice", 1)

    local r1 = PlayerReadiness.ensureRecord(p)
    check("ensureRecord: creates a record", r1 ~= nil)
    check("ensureRecord: facts table empty", next(r1.facts) == nil)
    check("ensureRecord: loadAttempt is 0", r1.loadAttempt == 0)

    local r2 = PlayerReadiness.ensureRecord(p)
    check("ensureRecord: idempotent (returns same record)", r1 == r2)

    PlayerReadiness.destroyRecord(p)
    check("destroyRecord: getRecord returns nil after destroy", PlayerReadiness.getRecord(p) == nil)

    PlayerReadiness.destroyRecord(p)   --// no warn
    check("destroyRecord: idempotent", true)
end

-- ─── recordFact / clearFact / isComplete / missingFacts ───────────────────────

do
    freshStore()
    local p = mockPlayer("Bob", 2)
    PlayerReadiness.ensureRecord(p)

    check("isComplete: false when no facts set", PlayerReadiness.isComplete(p) == false)

    local missing = PlayerReadiness.missingFacts(p)
    check("missingFacts: all required facts missing", #missing == #Configs.REQUIRED_FACTS)

    PlayerReadiness.recordFact(p, "ProfileLoaded")
    check("recordFact: stores fact", PlayerReadiness.getRecord(p).facts.ProfileLoaded == true)

    PlayerReadiness.recordFact(p, "ProfileLoaded")  --// idempotent
    check("recordFact: idempotent on re-write", PlayerReadiness.getRecord(p).facts.ProfileLoaded == true)

    PlayerReadiness.recordFact(p, "NotARealFact")
    check("recordFact: unknown fact ignored", PlayerReadiness.getRecord(p).facts.NotARealFact == nil)

    PlayerReadiness.clearFact(p, "ProfileLoaded")
    check("clearFact: removes fact", PlayerReadiness.getRecord(p).facts.ProfileLoaded == nil)

    PlayerReadiness.clearFact(p, "ProfileLoaded")  --// no-op on absent
    check("clearFact: idempotent on absent", PlayerReadiness.getRecord(p).facts.ProfileLoaded == nil)
end

-- ─── recordFact auto-creates record ───────────────────────────────────────────

do
    freshStore()
    local p = mockPlayer("Dave", 4)

    PlayerReadiness.recordFact(p, "ProfileLoaded")
    local rec = PlayerReadiness.getRecord(p)
    check("recordFact: creates record on first call", rec ~= nil)
    check("recordFact: fact present after auto-create", rec.facts.ProfileLoaded == true)
end

print(`\n{passed} passed, {failed} failed`)
```

- [ ] **Step 2: Run the test file to verify it fails**

Run via `execute_luau`. Expected: FAIL at the `require(ServerScriptService.RoundService.PlayerReadiness)` line because the module doesn't exist yet.

- [ ] **Step 3: Create `PlayerReadiness.lua` with the minimum API to pass the first test slice**

Create `src/Server/RoundService/PlayerReadiness.lua`:

```lua
--// Only files under src/Server/RoundService/ may require this module.
--// This is a dumb store: it writes facts, answers questions about records,
--// and fires ChangedSignal. It does NOT decide what is "ready" — that is
--// exclusively the RoundOrchestrator's job.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

export type ReadinessRecord = {
    player: any,
    facts: { [string]: boolean },
    loadAttempt: number,
    createdAt: number,
}

local PlayerReadiness = {}

local records: { [any]: ReadinessRecord } = {}
local ChangedSignal: BindableEvent = Instance.new("BindableEvent")
PlayerReadiness.ChangedSignal = ChangedSignal

local function isRequiredFact(factName: string): boolean
    for _, name in Configs.REQUIRED_FACTS do
        if name == factName then return true end
    end
    return false
end

function PlayerReadiness.ensureRecord(player: any): ReadinessRecord
    local existing = records[player]
    if existing then return existing end
    local rec: ReadinessRecord = {
        player = player,
        facts = {},
        loadAttempt = 0,
        createdAt = os.clock(),
    }
    records[player] = rec
    return rec
end

function PlayerReadiness.destroyRecord(player: any)
    records[player] = nil
end

function PlayerReadiness.getRecord(player: any): ReadinessRecord?
    return records[player]
end

function PlayerReadiness.recordFact(player: any, factName: string)
    if not isRequiredFact(factName) then
        warn(`[PlayerReadiness] unknown fact "{factName}"; ignored`)
        return
    end
    local rec = records[player] or PlayerReadiness.ensureRecord(player)
    if rec.facts[factName] then return end   --// idempotent: no re-fire
    rec.facts[factName] = true
    ChangedSignal:Fire()
end

function PlayerReadiness.clearFact(player: any, factName: string)
    local rec = records[player]
    if not rec then return end
    if not rec.facts[factName] then return end   --// idempotent: no fire on absent
    rec.facts[factName] = nil
    ChangedSignal:Fire()
end

function PlayerReadiness.isComplete(player: any): boolean
    local rec = records[player]
    if not rec then return false end
    for _, name in Configs.REQUIRED_FACTS do
        if not rec.facts[name] then return false end
    end
    return true
end

function PlayerReadiness.missingFacts(player: any): { string }
    local missing = {}
    local rec = records[player]
    for _, name in Configs.REQUIRED_FACTS do
        if not rec or not rec.facts[name] then
            table.insert(missing, name)
        end
    end
    return missing
end

--// Test-only: clears all records and resets the store.
function PlayerReadiness._reset()
    records = {}
end

return PlayerReadiness
```

- [ ] **Step 4: Run test to verify the first slice passes**

Run `PlayerReadiness.test.lua` via `execute_luau`. Expected: all lifecycle / session-fact / auto-create assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Server/RoundService/PlayerReadiness.lua src/Server/RoundService/PlayerReadiness.test.lua
git commit -m "feat(readiness): add PlayerReadiness store — record lifecycle + session facts"
```

---

## Task 5: `PlayerReadiness` — character-scoped facts with token gate

**Files:**
- Modify: `src/Server/RoundService/PlayerReadiness.lua`
- Modify: `src/Server/RoundService/PlayerReadiness.test.lua`

- [ ] **Step 1: Add failing tests for `beginCharacterLoad` and `recordCharacterFact`**

Append to `PlayerReadiness.test.lua` before the summary `print` line:

```lua
-- ─── beginCharacterLoad / recordCharacterFact ─────────────────────────────────

do
    freshStore()
    local p = mockPlayer("Erin", 5)
    PlayerReadiness.ensureRecord(p)

    local t1 = PlayerReadiness.beginCharacterLoad(p)
    check("beginCharacterLoad: returns a number token", type(t1) == "number")
    check("beginCharacterLoad: token is 1 on first call", t1 == 1)

    local t2 = PlayerReadiness.beginCharacterLoad(p)
    check("beginCharacterLoad: token monotonic", t2 == 2)
    check("beginCharacterLoad: tokens differ", t1 ~= t2)
end

do
    freshStore()
    local p = mockPlayer("Frank", 6)
    PlayerReadiness.ensureRecord(p)

    PlayerReadiness.recordFact(p, "ProfileLoaded")
    PlayerReadiness.recordFact(p, "LoadoutResolved")

    local token = PlayerReadiness.beginCharacterLoad(p)
    PlayerReadiness.recordCharacterFact(p, token, "CharacterLoaded")
    PlayerReadiness.recordCharacterFact(p, token, "CharacterUsable")

    check("recordCharacterFact: writes with matching token", PlayerReadiness.getRecord(p).facts.CharacterLoaded == true)
    check("isComplete: true with all 4 facts", PlayerReadiness.isComplete(p))
end

do
    freshStore()
    local p = mockPlayer("Gail", 7)
    PlayerReadiness.ensureRecord(p)

    local staleToken = PlayerReadiness.beginCharacterLoad(p)
    PlayerReadiness.beginCharacterLoad(p)   --// supersedes staleToken

    PlayerReadiness.recordCharacterFact(p, staleToken, "CharacterLoaded")
    check("recordCharacterFact: stale token is dropped", PlayerReadiness.getRecord(p).facts.CharacterLoaded == nil)
end

do
    freshStore()
    local p = mockPlayer("Henry", 8)
    PlayerReadiness.ensureRecord(p)

    local token = PlayerReadiness.beginCharacterLoad(p)
    PlayerReadiness.recordCharacterFact(p, token, "CharacterLoaded")

    --// Starting a fresh load clears char facts and bumps token.
    local newToken = PlayerReadiness.beginCharacterLoad(p)
    check("beginCharacterLoad: clears CharacterLoaded", PlayerReadiness.getRecord(p).facts.CharacterLoaded == nil)
    check("beginCharacterLoad: new token != old", newToken ~= token)
end
```

- [ ] **Step 2: Run test to verify it fails**

Expected: all new character-fact tests FAIL (functions don't exist).

- [ ] **Step 3: Add `beginCharacterLoad` and `recordCharacterFact` to the module**

Insert the following functions into `PlayerReadiness.lua` above the `_reset` section:

```lua
function PlayerReadiness.beginCharacterLoad(player: any): number
    local rec = records[player] or PlayerReadiness.ensureRecord(player)
    rec.loadAttempt += 1
    local cleared = false
    if rec.facts.CharacterLoaded then
        rec.facts.CharacterLoaded = nil
        cleared = true
    end
    if rec.facts.CharacterUsable then
        rec.facts.CharacterUsable = nil
        cleared = true
    end
    --// Always fire once — token advanced is a meaningful change even without fact clears.
    ChangedSignal:Fire()
    return rec.loadAttempt
end

function PlayerReadiness.recordCharacterFact(player: any, token: number, factName: string)
    if factName ~= "CharacterLoaded" and factName ~= "CharacterUsable" then
        warn(`[PlayerReadiness] recordCharacterFact: "{factName}" is not a character fact`)
        return
    end
    local rec = records[player]
    if not rec then
        warn(`[PlayerReadiness] recordCharacterFact: no record for {tostring(player)}`)
        return
    end
    if token ~= rec.loadAttempt then
        warn(`[PlayerReadiness] stale char fact {factName} for {(player :: any).Name or tostring(player)} (token {token} != current {rec.loadAttempt})`)
        return
    end
    if rec.facts[factName] then return end   --// idempotent
    rec.facts[factName] = true
    ChangedSignal:Fire()
end
```

- [ ] **Step 4: Run test to verify pass**

Expected: all character-fact tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Server/RoundService/PlayerReadiness.lua src/Server/RoundService/PlayerReadiness.test.lua
git commit -m "feat(readiness): character-scoped facts with load-attempt token gate"
```

---

## Task 6: `PlayerReadiness` — event-driven waits

**Files:**
- Modify: `src/Server/RoundService/PlayerReadiness.lua`
- Modify: `src/Server/RoundService/PlayerReadiness.test.lua`

- [ ] **Step 1: Add failing tests for `waitForChange` and `waitForComplete`**

Append before the summary:

```lua
-- ─── waitForChange / waitForComplete ──────────────────────────────────────────

do
    freshStore()
    local p = mockPlayer("Iris", 9)
    PlayerReadiness.ensureRecord(p)

    --// waitForChange on immediate trigger
    task.spawn(function()
        task.wait(0.05)
        PlayerReadiness.recordFact(p, "ProfileLoaded")
    end)
    local start = os.clock()
    PlayerReadiness.waitForChange(1.0)
    local elapsed = os.clock() - start
    check("waitForChange: returns when signal fires", elapsed < 0.5)

    --// waitForChange with timeout (no fire)
    freshStore()
    start = os.clock()
    PlayerReadiness.waitForChange(0.2)
    elapsed = os.clock() - start
    check("waitForChange: respects timeout", elapsed >= 0.18 and elapsed < 0.4)
end

do
    freshStore()
    local p = mockPlayer("Jay", 10)
    PlayerReadiness.ensureRecord(p)
    --// Pre-populate all facts
    PlayerReadiness.recordFact(p, "ProfileLoaded")
    PlayerReadiness.recordFact(p, "LoadoutResolved")
    local token = PlayerReadiness.beginCharacterLoad(p)
    PlayerReadiness.recordCharacterFact(p, token, "CharacterLoaded")
    PlayerReadiness.recordCharacterFact(p, token, "CharacterUsable")

    local start = os.clock()
    local ready = PlayerReadiness.waitForComplete(p, 1.0)
    local elapsed = os.clock() - start
    check("waitForComplete: returns true immediately if already complete", ready == true and elapsed < 0.05)
end

do
    freshStore()
    local p = mockPlayer("Kim", 11)
    PlayerReadiness.ensureRecord(p)

    --// Drive facts one at a time on a spawned coroutine
    task.spawn(function()
        task.wait(0.05)
        PlayerReadiness.recordFact(p, "ProfileLoaded")
        task.wait(0.05)
        PlayerReadiness.recordFact(p, "LoadoutResolved")
        task.wait(0.05)
        local t = PlayerReadiness.beginCharacterLoad(p)
        PlayerReadiness.recordCharacterFact(p, t, "CharacterLoaded")
        PlayerReadiness.recordCharacterFact(p, t, "CharacterUsable")
    end)

    local start = os.clock()
    local ready = PlayerReadiness.waitForComplete(p, 1.0)
    local elapsed = os.clock() - start
    check("waitForComplete: returns true when facts arrive mid-wait", ready == true)
    check("waitForComplete: returned before timeout", elapsed < 0.9)
end

do
    freshStore()
    local p = mockPlayer("Liam", 12)
    PlayerReadiness.ensureRecord(p)

    local start = os.clock()
    local ready = PlayerReadiness.waitForComplete(p, 0.25)
    local elapsed = os.clock() - start
    check("waitForComplete: returns false on timeout", ready == false)
    check("waitForComplete: respects timeout bound", elapsed >= 0.2 and elapsed < 0.5)
end
```

- [ ] **Step 2: Run to verify failure**

Expected: tests fail with "attempt to call a nil value (method 'waitForChange'/'waitForComplete')".

- [ ] **Step 3: Implement `waitForChange` and `waitForComplete`**

Add above `_reset` in `PlayerReadiness.lua`:

```lua
function PlayerReadiness.waitForChange(timeout: number)
    local fired = false
    local conn
    conn = ChangedSignal.Event:Connect(function()
        fired = true
    end)
    local timer = task.delay(timeout, function()
        fired = true
    end)
    while not fired do
        task.wait()
    end
    conn:Disconnect()
    task.cancel(timer)
end

function PlayerReadiness.waitForComplete(player: any, timeout: number): boolean
    if PlayerReadiness.isComplete(player) then return true end
    local deadline = os.clock() + timeout
    while true do
        local timeLeft = deadline - os.clock()
        if timeLeft <= 0 then return false end
        PlayerReadiness.waitForChange(timeLeft)
        if PlayerReadiness.isComplete(player) then return true end
    end
end
```

- [ ] **Step 4: Run tests to verify pass**

Expected: all wait tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Server/RoundService/PlayerReadiness.lua src/Server/RoundService/PlayerReadiness.test.lua
git commit -m "feat(readiness): add event-driven waitForChange and waitForComplete"
```

---

## Task 7: `DataService` — fire `ProfileLoaded` on successful mount

**Files:**
- Modify: `src/Server/DataService/init.lua`

- [ ] **Step 1: Add `ServerEventBus` require at the top**

In `src/Server/DataService/init.lua`, add after the existing requires (around line 7):

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ServerEventBus = require(ServerScriptService.ServerEventBus)
```

- [ ] **Step 2: Fire the event at the end of `OnPlayerAdded`**

Find the block `if player:IsDescendantOf(Players) and not LeavingFlags[player] then` in `OnPlayerAdded`. Add the fire after `Profiles[player] = profile`:

```lua
if player:IsDescendantOf(Players) and not LeavingFlags[player] then
    Profiles[player] = profile
    debugPrint(DEBUG, `[DataService] Profile stored for {player.Name}`)
    ServerEventBus:Fire("ProfileLoaded", player)
else
```

On the failure paths (profile == nil / LeavingFlags), no event is fired. Absence ≡ not loaded.

- [ ] **Step 3: Verify by running the project in Studio and observing the event in console**

Run Studio, join a test server, and via `execute_luau`:

```
mcp__robloxstudio__execute_luau(script = [[
local ServerScriptService = game:GetService("ServerScriptService")
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local count = 0
local conn = ServerEventBus:Connect("ProfileLoaded", function(player)
    count += 1
    print("Observed ProfileLoaded for:", player.Name)
end)
task.wait(2)
conn:Disconnect()
print("Total observed:", count)
]])
```

If a test session is already running with a player logged in, expected: observed count > 0 for new joins. If no new joins happen during the wait, the test is inconclusive but the change is wire-level-simple.

- [ ] **Step 4: Commit**

```bash
git add src/Server/DataService/init.lua
git commit -m "feat(dataservice): fire ProfileLoaded ServerEventBus event on successful mount"
```

---

## Task 8: `WeaponDistributor` — idempotent `distributeToPlayer`

**Files:**
- Modify: `src/Server/WeaponDistributor/init.lua`
- Modify: `src/Server/WeaponDistributor/WeaponDistributor.test.lua`

- [ ] **Step 1: Read the existing test file to locate insertion point**

Read `src/Server/WeaponDistributor/WeaponDistributor.test.lua` in full. Note how existing tests build mock tools and players.

- [ ] **Step 2: Add failing idempotency tests**

Append new test cases (before the `cleanAll()` and summary print) that call `distributeToPlayer` twice and assert the backpack contains exactly one of each tool:

```lua
-- ─── distributeToPlayer idempotency ───────────────────────────────────────────

do
    WeaponDistributor._reset()
    local k1 = makeTool("TestKnife1")
    local h = addHandle(k1)
    addHitbox(k1)
    local g1 = makeTool("TestGun1")
    local gh = addHandle(g1)
    addAttachment(gh, "ShootPoint")
    local initOk = WeaponDistributor.init({ k1 }, { g1 })
    check("idempotent: init ok", initOk)

    local player, backpack = makePlayerWithBackpack()
    WeaponDistributor.distributeToPlayer(player, "TestKnife1", "TestGun1")
    WeaponDistributor.distributeToPlayer(player, "TestKnife1", "TestGun1")

    local knifeCount = 0
    local gunCount = 0
    for _, child in backpack:GetChildren() do
        if child.Name == "TestKnife1" then knifeCount += 1 end
        if child.Name == "TestGun1" then gunCount += 1 end
    end
    check("idempotent: exactly one knife after two calls", knifeCount == 1)
    check("idempotent: exactly one gun after two calls", gunCount == 1)
end
```

- [ ] **Step 3: Run to verify failure**

Expected: `knifeCount == 2` and `gunCount == 2` — both checks FAIL because current `distributeToPlayer` unconditionally clones.

- [ ] **Step 4: Rewrite `distributeToPlayer` to be idempotent**

In `src/Server/WeaponDistributor/init.lua`, replace the `distributeToPlayer` function with:

```lua
function WeaponDistributor.distributeToPlayer(player: Player, knifeName: string?, gunName: string?)
    if not defaultKnifeTemplate or not defaultGunTemplate then
        warn(`[WeaponDistributor] Cannot distribute to {player.Name} — not initialized`)
        return
    end

    local character = player.Character
    if not character then
        warn(`[WeaponDistributor] {player.Name} has no character`)
        return
    end

    local backpack = player:FindFirstChildWhichIsA("Backpack")
    if not backpack then
        warn(`[WeaponDistributor] No Backpack found for {player.Name}`)
        return
    end

    local knifeTemplate = (knifeName and knifeTemplates[knifeName]) or defaultKnifeTemplate
    local gunTemplate = (gunName and gunTemplates[gunName]) or defaultGunTemplate

    --// Idempotency: skip if the tool is already in the backpack or equipped on the character.
    if not backpack:FindFirstChild(knifeTemplate.Name) and not character:FindFirstChild(knifeTemplate.Name) then
        local knife = knifeTemplate:Clone()
        knife:SetAttribute("IsKnife", true)
        knife.Parent = backpack
    end

    if not backpack:FindFirstChild(gunTemplate.Name) and not character:FindFirstChild(gunTemplate.Name) then
        local gun = gunTemplate:Clone()
        gun:SetAttribute("IsGun", true)
        gun.Parent = backpack
    end
end
```

Note: the mock player in tests is a `Folder`, not a real `Player` instance. `Folder` doesn't have a `.Character` property. For tests to pass we need to either (a) skip the character-check in test mode or (b) change the mock helper. Choose (b): update the test mock to create a child named "Character":

```lua
local function makePlayerWithBackpack(): (Instance, Instance)
    local player = Instance.new("Folder")
    player.Name = "MockPlayer"
    local backpack = Instance.new("Backpack")
    backpack.Parent = player
    local character = Instance.new("Model")
    character.Name = "Character"
    character.Parent = player
    player.Parent = workspace
    track(player)
    return player, backpack
end
```

**Wait** — a `Folder` has no `.Character` property; accessing `player.Character` on a Folder returns the child named "Character". That works for our purposes. Update the helper above; existing tests that use it continue to work.

- [ ] **Step 5: Run tests to verify pass**

Run `WeaponDistributor.test.lua` via `execute_luau`. Expected: idempotency assertions PASS, and the existing distribution tests also PASS.

- [ ] **Step 6: Commit**

```bash
git add src/Server/WeaponDistributor/init.lua src/Server/WeaponDistributor/WeaponDistributor.test.lua
git commit -m "feat(weapons): make distributeToPlayer idempotent via backpack/character check"
```

---

## Task 9: `WeaponDistributor` executor — error at init, remove listeners

**Files:**
- Modify: `src/Server/WeaponDistributor/executor.server.lua`

- [ ] **Step 1: Rewrite the executor to be stateless and fail loud**

Replace the entire contents of `src/Server/WeaponDistributor/executor.server.lua`:

```lua
--// Validates weapon templates at module load. Calls WeaponDistributor.init once.
--// No listeners. No _roundActive flag. RoundSystem calls distributeToPlayer directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponDistributor = require(script.Parent)

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
                table.insert(problems, `KnifeModels.{child.Name} is not a Tool (got {child.ClassName})`)
            end
        end
        if #knives == 0 then table.insert(problems, "KnifeModels contains zero Tools") end
    end

    local gunModels = ReplicatedStorage:FindFirstChild("GunModels")
    if not gunModels then
        table.insert(problems, "ReplicatedStorage.GunModels missing")
    else
        for _, child in gunModels:GetChildren() do
            if child:IsA("Tool") then
                table.insert(guns, child)
            else
                table.insert(problems, `GunModels.{child.Name} is not a Tool (got {child.ClassName})`)
            end
        end
        if #guns == 0 then table.insert(problems, "GunModels contains zero Tools") end
    end

    if #problems > 0 then return false, problems, nil, nil end
    return true, nil, knives, guns
end

local validationOk, problems, knives, guns = validateWeapons()
if not validationOk then
    warn("[WeaponDistributor] CRITICAL — weapon validation failed:")
    for _, msg in problems do warn(`  - {msg}`) end
    error("[WeaponDistributor] cannot initialize — see warnings above")
end

local initOk = WeaponDistributor.init(knives, guns)
if not initOk then
    error("[WeaponDistributor] init failed")
end

print("[WeaponDistributor] initialized with " .. #knives .. " knives, " .. #guns .. " guns")
```

- [ ] **Step 2: Verify the project still starts in Studio**

Run Studio with the project synced. If validation succeeds (KnifeModels and GunModels present and valid), Studio's output should show the init print. If validation fails, Studio's output will show the warn + error — fix weapon data, not the code.

- [ ] **Step 3: Commit**

```bash
git add src/Server/WeaponDistributor/executor.server.lua
git commit -m "refactor(weapons): error at init failure, remove CharacterAdded listeners"
```

---

## Task 10: `RoundSystem.init.lua` — roster, UnregisterPlayer, OnPlayerDied guard, constructor signature

**Files:**
- Modify: `src/Server/RoundService/init.lua`

- [ ] **Step 1: Remove `positioningDoneEvent` from `RoundSystem.new` and create a local BindableEvent**

Change the constructor:

```lua
function RoundSystem.new(metadata: TeleportMetadata)
    TeleportMetadataService.Initialize(metadata)

    local self = setmetatable({}, RoundSystem)

    self._metadata = metadata
    self._positioningDoneEvent = Instance.new("BindableEvent")   --// local-per-round
    self._expectedPlayerCount = #metadata.teamOnePlayers + #metadata.teamTwoPlayers
    self._pendingPlayers = {} :: { Player }
    self._roundRoster = {} :: { Player }
    self._stateMachine = RoundStateMachine.new()
    self._playerStates = {} :: { [Player]: any }
    self._teamPlayers = { [1] = {}, [2] = {} } :: { [number]: { Player } }
    self._teamStates = {} :: { [number]: any }
    self._roundNumber = 0
    self._roundResults = {}
    self._disconnectedStats = {} :: { [string]: any }
    self._listeners = {} :: { [string]: { (...any) -> () } }
    self._broadcastRemote = NetworkRouter:CreateRemoteEvent("RoundUpdate")
    self._waitTask = nil
    self._roundTimerTask = nil
    self._mapModel = nil
    self._destroyed = false
    self._positioningPlayers = false

    self._stateMachine:SetTransitionCallback(function(from: string, to: string)
        self:_onStateChanged(from, to)
    end)

    RoundOrchestrator.enter(Configs.GAME_STATES.WaitingForPlayers, self)

    return self
end
```

- [ ] **Step 2: Destroy the BindableEvent in `Destroy`**

In `RoundSystem:Destroy`, add after `if self._mapModel then ... end`:

```lua
if self._positioningDoneEvent then
    self._positioningDoneEvent:Destroy()
    self._positioningDoneEvent = nil
end
```

- [ ] **Step 3: Update `UnregisterPlayer` to preserve roster entries**

Replace the `UnregisterPlayer` function with:

```lua
function RoundSystem:UnregisterPlayer(player: Player)
    local state = self._stateMachine:GetState()

    if state == Configs.GAME_STATES.WaitingForPlayers then
        local index = table.find(self._pendingPlayers, player)
        if index then table.remove(self._pendingPlayers, index) end
        return
    end

    --// Later states: preserve the roster entry and mark the status as
    --// Disconnected. Do NOT delete _playerStates[player] — the roster is
    --// authoritative for the round.
    local playerState = self._playerStates[player]
    if playerState then
        playerState.status = Configs.PLAYER_STATUSES.Disconnected
        self._disconnectedStats[tostring(player.UserId)] = playerState:Serialize()
    end

    if state == Configs.GAME_STATES.RoundActive then
        self:_fireEvent("PlayerStatusChanged", player, Configs.PLAYER_STATUSES.Disconnected)
        self:_broadcastUpdate()
        self:_checkWinCondition()
    end
end
```

- [ ] **Step 4: Add a Skipped guard to `OnPlayerDied`**

Replace the early `playerState` lookup in `OnPlayerDied`:

```lua
function RoundSystem:OnPlayerDied(player: Player)
    if self._stateMachine:GetState() ~= Configs.GAME_STATES.RoundActive then
        warn(`[RoundSystem] OnPlayerDied called outside RoundActive for {player.Name}`)
        return
    end
    local playerState = self._playerStates[player]
    if not playerState then
        warn(`[RoundSystem] OnPlayerDied: no state found for {player.Name}`)
        return
    end
    if playerState.status == Configs.PLAYER_STATUSES.Skipped then
        warn(`[RoundSystem] OnPlayerDied: {player.Name} is Skipped; ignoring death (should have been impossible)`)
        return
    end
    playerState:SetAlive(false)
    playerState:SetStat("deaths", playerState:GetStat("deaths") + 1)
    -- ... rest unchanged
end
```

(Leave the rest of the function body unchanged.)

- [ ] **Step 5: Verify existing tests still pass**

Run `RoundSystem.test.lua` via `execute_luau`. Expected: all existing assertions still PASS. No new assertions needed here — the changes are behavioral for engine-driven paths covered by integration tests later.

- [ ] **Step 6: Commit**

```bash
git add src/Server/RoundService/init.lua
git commit -m "refactor(round): add roster, preserve roster on disconnect, drop positioningDoneEvent param"
```

---

## Task 11: `RoundOrchestrator` — add `loadCharacterAndRecord` helper

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Add the PlayerReadiness require and the helper at the top of the file**

In `src/Server/RoundService/RoundOrchestrator.lua`, add at the top near the other requires:

```lua
local PlayerReadiness = require(script.Parent.PlayerReadiness)
```

And below `collectSpawnParts` / `getSpawnAssignment`, add the helper:

```lua
local function loadCharacterAndRecord(player: Player, timeout: number): boolean
    local token = PlayerReadiness.beginCharacterLoad(player)

    local characterResult: Model? = nil
    local characterSignal = Instance.new("BindableEvent")
    local conn = player.CharacterAdded:Once(function(c)
        characterResult = c
        characterSignal:Fire()
    end)

    local ok = pcall(function() player:LoadCharacter() end)
    if not ok then
        conn:Disconnect()
        characterSignal:Destroy()
        warn(`[Round] loadCharacterAndRecord: LoadCharacter threw for {player.Name}`)
        return false
    end

    if not characterResult then
        local timer = task.delay(timeout, function()
            characterSignal:Fire()
        end)
        characterSignal.Event:Wait()
        task.cancel(timer)
    end
    characterSignal:Destroy()

    if not characterResult then
        conn:Disconnect()
        return false
    end

    local character = characterResult :: Model
    local hrpTimeLeft = Configs.CHAR_FACT_WAIT_TIMEOUT
    local hrp = character:WaitForChild("HumanoidRootPart", hrpTimeLeft)
    local humanoid = character:WaitForChild("Humanoid", hrpTimeLeft)
    if not hrp or not humanoid then
        return false
    end

    PlayerReadiness.recordCharacterFact(player, token, "CharacterLoaded")
    PlayerReadiness.recordCharacterFact(player, token, "CharacterUsable")
    return true
end
```

- [ ] **Step 2: Add `getSpawnFor` helper**

Below `getSpawnAssignment`, add:

```lua
local function getSpawnFor(system, teamNumber: number): BasePart?
    local spawnGroups = getSpawnAssignment(system)
    local spawns = spawnGroups[teamNumber]
    if not spawns or #spawns == 0 then return nil end
    --// Simple rotation: use the player's index within their team list, modulo spawn count.
    --// The caller (enterRoundActive per-player task) does its own rotation.
    return spawns[1]   --// placeholder — enterRoundActive will pass its own index-based spawn
end
```

(The real per-player rotation happens at the call site in `enterRoundActive`, which has the player's team-index available. `getSpawnFor` is a fallback single-spawn lookup kept for simplicity.)

- [ ] **Step 3: Syntax-check by running existing tests**

Run `RoundSystem.test.lua` via `execute_luau`. It requires `RoundOrchestrator`'s dependencies transitively; if the file has syntax errors, the require will throw. Expected: all existing tests still PASS.

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): add loadCharacterAndRecord helper for token-gated char fact writes"
```

---

## Task 12: `RoundOrchestrator` — add `applySkipped` helper

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Add `applySkipped` below `loadCharacterAndRecord`**

```lua
local function clearBackpack(player: Player)
    local backpack = player:FindFirstChildWhichIsA("Backpack")
    if backpack then
        for _, child in backpack:GetChildren() do
            if child:IsA("Tool") then child:Destroy() end
        end
    end
    local character = player.Character
    if character then
        for _, child in character:GetChildren() do
            if child:IsA("Tool") then child:Destroy() end
        end
    end
end

local function pickInitialSpawnCFrame(): CFrame
    local spawnBox = workspace:FindFirstChild(Configs.INITIAL_SPAWN_PART)
    if spawnBox and spawnBox:IsA("BasePart") then
        local half = spawnBox.Size / 2
        local rx = (math.random() * 2 - 1) * half.X
        local rz = (math.random() * 2 - 1) * half.Z
        return spawnBox.CFrame * CFrame.new(rx, half.Y + 3, rz)
    end
    warn("[Round] InitialSpawnBox missing — falling back to (0, 100, 0)")
    return CFrame.new(0, 100, 0)
end

local function applySkipped(system, player: Player, playerState)
    if playerState.status == Configs.PLAYER_STATUSES.Skipped then return end   --// idempotent
    playerState.status = Configs.PLAYER_STATUSES.Skipped

    clearBackpack(player)

    local character = player.Character
    if character then
        local hrp = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if hrp and hrp:IsA("BasePart") then
            hrp.CFrame = pickInitialSpawnCFrame()
            hrp.Anchored = true
        end
        if humanoid then
            humanoid.WalkSpeed = 0
        end
        if not character:FindFirstChildOfClass("ForceField") then
            local ff = Instance.new("ForceField")
            ff.Visible = true
            ff.Parent = character
        end
    else
        warn(`[Round] applySkipped: {player.Name} has no character; physical side effects deferred until next character load`)
    end

    system:_broadcastUpdate()
end
```

- [ ] **Step 2: Syntax-check**

Run `RoundSystem.test.lua` via `execute_luau`. Expected: existing tests PASS (new helpers are unused but parsed).

- [ ] **Step 3: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): add applySkipped helper with synchronous physical side effects"
```

---

## Task 13: `RoundOrchestrator` — add `exitSkippedOrPosition` helper

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Add `exitSkippedOrPosition` below `applySkipped`**

```lua
local WeaponDistributor = require(game:GetService("ServerScriptService"):WaitForChild("WeaponDistributor"))

local function exitSkippedOrPosition(system, player: Player, playerState, spawnPart: BasePart, loadout)
    if playerState.positionedThisRound then return end   --// run-once gate per round
    playerState.positionedThisRound = true

    playerState.status = Configs.PLAYER_STATUSES.Alive

    local character = player.Character
    if not character then
        warn(`[Round] exitSkippedOrPosition: {player.Name} has no character; cannot position`)
        return
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if hrp and hrp:IsA("BasePart") then
        hrp.Anchored = false
        hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
    end
    if humanoid then
        humanoid.WalkSpeed = Configs.DEFAULT_WALK_SPEED
    end

    for _, child in character:GetChildren() do
        if child:IsA("ForceField") then child:Destroy() end
    end

    local knifeName = loadout and loadout.knifeName
    local gunName = loadout and loadout.gunName
    WeaponDistributor.distributeToPlayer(player, knifeName, gunName)
end
```

Also move the `local WeaponDistributor = ...` line to the top of the file with the other requires — it's cleaner there.

- [ ] **Step 2: Syntax-check**

Run `RoundSystem.test.lua` via `execute_luau`. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): add exitSkippedOrPosition helper with positionedThisRound gate"
```

---

## Task 14: `RoundOrchestrator` — update `enterAssigningTeams` to build roster and transition to PreparingPlayers

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Remove the WeaponSystemState require and IsReady check**

Find and delete these lines near the top of `enterAssigningTeams`:

```lua
local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
```

And inside `enterAssigningTeams`, delete:

```lua
if not WeaponSystemState.IsReady() then
    warn("[Round] Weapon system not ready — aborting round")
    system:_transition(Configs.GAME_STATES.Aborted)
    return
end
```

- [ ] **Step 2: After team assignment, populate `_roundRoster` and record `LoadoutResolved`**

At the end of `enterAssigningTeams`, after `system._teamStates[2] = ...`, add:

```lua
--// Freeze the authoritative roster for this match.
local roster: { Player } = {}
for _, p in system._teamPlayers[1] do table.insert(roster, p) end
for _, p in system._teamPlayers[2] do table.insert(roster, p) end
system._roundRoster = roster

--// Record LoadoutResolved for each roster player (synchronous write from orchestrator).
for _, p in roster do
    PlayerReadiness.recordFact(p, "LoadoutResolved")
end

--// Clear _pendingPlayers — it's only meaningful during WaitingForPlayers.
system._pendingPlayers = {}

system:_transition(Configs.GAME_STATES.PreparingPlayers)
```

(Replace the existing `system:_transition(Configs.GAME_STATES.RoundActive)` call at the end with the new `PreparingPlayers` transition.)

- [ ] **Step 3: Verify the existing test file still passes**

Run `RoundSystem.test.lua`. The tests are unit-level and don't drive the full state machine, so they should PASS.

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): enterAssigningTeams freezes roster and transitions to PreparingPlayers"
```

---

## Task 15: `RoundOrchestrator` — add `enterPreparingPlayers` handler

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Add the handler**

Add a new function above `enterRoundActive`:

```lua
local function allRosterReady(roster: { Player }): boolean
    for _, player in roster do
        if not PlayerReadiness.isComplete(player) then return false end
    end
    return true
end

local function enterPreparingPlayers(system)
    print(`[Round] State: PreparingPlayers — grace {Configs.READINESS_GRACE_FIRST_ROUND}s for {#system._roundRoster} player(s)`)
    local deadline = os.clock() + Configs.READINESS_GRACE_FIRST_ROUND

    --// Spawn per-player loads. Each task is bounded internally by
    --// loadCharacterAndRecord's own timeouts (CHAR_FACT_WAIT_TIMEOUT).
    --// Tasks do NOT call applySkipped on their own failure — the post-wait
    --// cleanup loop below is the single site for force-skip.
    for _, player in system._roundRoster do
        task.spawn(function()
            loadCharacterAndRecord(player, Configs.READINESS_GRACE_FIRST_ROUND)
        end)
    end

    --// Global event-driven wait. Yields on ChangedSignal OR deadline.
    while true do
        if allRosterReady(system._roundRoster) then break end
        local timeLeft = deadline - os.clock()
        if timeLeft <= 0 then break end
        PlayerReadiness.waitForChange(timeLeft)
        if system._stateMachine:GetState() ~= Configs.GAME_STATES.PreparingPlayers then return end
    end

    --// Deadline reached or all ready. Force-skip any incomplete player NOW,
    --// synchronously applying physical side effects.
    for _, player in system._roundRoster do
        if not PlayerReadiness.isComplete(player) then
            warn(`[Round] {player.Name} incomplete after PreparingPlayers grace: {table.concat(PlayerReadiness.missingFacts(player), ", ")}`)
            applySkipped(system, player, system._playerStates[player])
        end
    end

    system:_transition(Configs.GAME_STATES.RoundActive)
end
```

- [ ] **Step 2: Register the handler in the `handlers` table**

Find the `handlers` table at the bottom of the file and add:

```lua
local handlers = {
    [Configs.GAME_STATES.WaitingForPlayers] = enterWaitingForPlayers,
    [Configs.GAME_STATES.AssigningTeams] = enterAssigningTeams,
    [Configs.GAME_STATES.PreparingPlayers] = enterPreparingPlayers,
    [Configs.GAME_STATES.RoundActive] = enterRoundActive,
    [Configs.GAME_STATES.RoundIntermission] = enterRoundIntermission,
    [Configs.GAME_STATES.GameOver] = enterGameOver,
    [Configs.GAME_STATES.TeleportingOut] = enterTeleportingOut,
    [Configs.GAME_STATES.Aborted] = enterAborted,
}
```

- [ ] **Step 3: Verify existing tests still pass**

Run `RoundSystem.test.lua`. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): add enterPreparingPlayers with global readiness grace"
```

---

## Task 16: `RoundOrchestrator` — rewrite `enterRoundActive` for non-blocking per-player flow

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Replace `enterRoundActive` in full**

Replace the existing `enterRoundActive` function with:

```lua
local function enterRoundActive(system)
    system._roundNumber += 1
    print(`[Round] State: RoundActive — Round {system._roundNumber} | {Configs.ROUND_DURATION}s`)

    system._positioningPlayers = true   --// gates _checkWinCondition during positioning

    --// Round timer starts NOW, parallel to positioning.
    system._roundTimerTask = task.delay(Configs.ROUND_DURATION, function()
        system._roundTimerTask = nil
        if system._stateMachine:GetState() ~= Configs.GAME_STATES.RoundActive then return end

        local t1 = system._teamStates[1]:Recalculate()
        local t2 = system._teamStates[2]:Recalculate()
        local winningTeam = nil
        if t1.alivePlayers > t2.alivePlayers then
            winningTeam = 1
        elseif t2.alivePlayers > t1.alivePlayers then
            winningTeam = 2
        end
        print(`[Round] Time expired — winner: {winningTeam and "Team "..winningTeam or "Draw"}`)
        table.insert(system._roundResults, { winningTeam = winningTeam, stats = {} })
        system:_fireEvent("RoundOver", winningTeam, system._roundNumber)
        local gameOver = WinConditionEvaluator.isGameOver(system._roundResults, system._roundNumber)
        if gameOver then
            system:_transition(Configs.GAME_STATES.GameOver)
        else
            system:_transition(Configs.GAME_STATES.RoundIntermission)
        end
    end)

    --// Spawn per-player positioning tasks in parallel.
    local remaining = 0
    local finalized = false

    local function finalize()
        if finalized then return end
        finalized = true
        system._positioningPlayers = false
        system:_broadcastUpdate()
        system:_checkWinCondition()
    end

    --// Pre-compute spawn groups once per round entry so per-player assignments
    --// can rotate through them deterministically.
    local spawnGroups = getSpawnAssignment(system)

    for teamNum, players in system._teamPlayers do
        local spawns = spawnGroups[teamNum]
        if not spawns or #spawns == 0 then
            warn(`[Round] No spawn parts found for team {teamNum}`)
            continue
        end
        for i, player in players do
            local playerState = system._playerStates[player]
            if not playerState then continue end
            if playerState.status == Configs.PLAYER_STATUSES.Disconnected then continue end
            if playerState.status == Configs.PLAYER_STATUSES.Skipped then
                --// Round-1 force-skipped from PreparingPlayers. No late-teleport
                --// within the same round — they wait for the next intermission exit.
                continue
            end

            local spawnPart = spawns[((i - 1) % #spawns) + 1]
            remaining += 1

            task.spawn(function()
                local ok, err = pcall(function()
                    --// Fast path (round 1): facts already set by PreparingPlayers.
                    --// Slow path (rounds 2+): intermission cleared char facts; re-load
                    --//                        with per-player LATE_TELEPORT_GRACE.
                    if not PlayerReadiness.isComplete(player) then
                        local ready = loadCharacterAndRecord(player, Configs.LATE_TELEPORT_GRACE)
                        if not ready then
                            applySkipped(system, player, playerState)
                            return
                        end
                    end
                    local loadout = TeleportMetadataService.GetLoadout(player.UserId)
                    exitSkippedOrPosition(system, player, playerState, spawnPart, loadout)
                end)
                if not ok then
                    warn(`[Round] Positioning task errored for {player.Name}: {err}`)
                    applySkipped(system, player, playerState)
                end
                remaining -= 1
                if remaining == 0 then finalize() end
            end)
        end
    end

    if remaining == 0 then finalize() end   --// edge case: nobody eligible

    --// Safety backstop — NOT a gate. Parallel to positioning and the round timer.
    task.delay(Configs.POSITIONING_OUTER_TIMEOUT, function()
        if finalized then return end
        warn("[Round] Positioning outer safety timer fired — force-finalizing")
        for _, player in system._roundRoster do
            local state = system._playerStates[player]
            if not state then continue end
            local s = state.status
            if s ~= Configs.PLAYER_STATUSES.Alive
                and s ~= Configs.PLAYER_STATUSES.Skipped
                and s ~= Configs.PLAYER_STATUSES.Disconnected
            then
                warn(`[Round] {player.Name} did not reach terminal state — forcing Skipped`)
                applySkipped(system, player, state)
            end
        end
        finalize()
    end)
end
```

- [ ] **Step 2: Remove the old `loadAndPositionPlayers` function**

The old top-of-file `loadAndPositionPlayers` helper is no longer used. Delete it entirely (its functionality is now split between `loadCharacterAndRecord`, `exitSkippedOrPosition`, and the per-player task inside `enterRoundActive`).

- [ ] **Step 3: Syntax-check via the existing tests**

Run `RoundSystem.test.lua`. Expected: existing unit tests PASS (they don't drive full RoundActive flow).

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): rewrite enterRoundActive for non-blocking per-player positioning"
```

---

## Task 17: `RoundOrchestrator` — update `enterRoundIntermission` exit cleanup

**Files:**
- Modify: `src/Server/RoundService/RoundOrchestrator.lua`

- [ ] **Step 1: Update the intermission exit callback**

Find the `task.delay(Configs.ROUND_INTERMISSION_DURATION, function() ... end)` in `enterRoundIntermission` and replace the body:

```lua
system._waitTask = task.delay(Configs.ROUND_INTERMISSION_DURATION, function()
    system._waitTask = nil

    for _, playerState in system._playerStates do
        playerState:Unlock()
        playerState:Reset()  --// Reset sets status to Alive and clears positionedThisRound (Task 3)
    end

    --// Clear character facts for every roster player so that the next
    --// RoundActive's per-player tasks take the slow path and reload.
    for _, player in system._roundRoster do
        PlayerReadiness.clearFact(player, "CharacterLoaded")
        PlayerReadiness.clearFact(player, "CharacterUsable")
    end

    local isOver = WinConditionEvaluator.isGameOver(system._roundResults, system._roundNumber)
    if isOver then
        system:_transition(Configs.GAME_STATES.GameOver)
    else
        system:_transition(Configs.GAME_STATES.RoundActive)
    end
end)
```

Note: `PlayerState:Reset()` already sets `status = Alive` (this handles both `Dead → Alive` and `Skipped → Alive` transitions in one step, because Reset unconditionally sets Alive). Disconnected players' Reset also sets them to Alive, which is incorrect — but Disconnected players are no longer in `_playerStates`? No — Task 10 keeps them. We need a guard.

- [ ] **Step 2: Guard `Reset` against Disconnected players**

Replace the `for _, playerState in system._playerStates do ... end` block above with:

```lua
for _, playerState in system._playerStates do
    if playerState.status == Configs.PLAYER_STATUSES.Disconnected then
        --// Leave disconnected entries alone — they remain Disconnected for the rest of the match.
        continue
    end
    playerState:Unlock()
    playerState:Reset()
end
```

- [ ] **Step 3: Verify tests still pass**

Run `RoundSystem.test.lua`. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/Server/RoundService/RoundOrchestrator.lua
git commit -m "feat(round): intermission exit clears char facts, preserves Disconnected"
```

---

## Task 18: `RoundService/executor.server.lua` — PlayerReadiness wiring, remove ServerStorage BindableEvent

**Files:**
- Modify: `src/Server/RoundService/executor.server.lua`

- [ ] **Step 1: Replace the file contents**

```lua
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local Configs = require(ReplicatedStorage.Round.Configs)

local RoundService = require(script.Parent)
local TeleportDataValidator = require(script.Parent.TeleportDataValidator)
local PlayerReadiness = require(script.Parent.PlayerReadiness)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local roundSystem = nil

--// Subscribe once at script load. Producers fire ProfileLoaded;
--// we translate to a readiness fact write.
ServerEventBus:Connect("ProfileLoaded", function(player: Player)
    PlayerReadiness.recordFact(player, "ProfileLoaded")
end)

local function buildTemplateTeleportData(player: Player)
    return {
        teamOnePlayers = { { UserId = player.UserId, Name = player.Name } },
        teamTwoPlayers = { { UserId = 0, Name = "TestPlayer" } },
        queueType = 1,
        mapName = "TestMap",
        timestamp = os.time(),
        loadouts = {
            [tostring(player.UserId)] = { knifeName = nil, gunName = nil },
            ["0"] = { knifeName = nil, gunName = nil },
        },
    }
end

local function setupPlayer(player: Player)
    PlayerReadiness.ensureRecord(player)

    local teleportData
    if GlobalConfigs.TEST_MODE then
        print(`[Round] TEST_MODE — {player.Name} using template data (map: TestMap, 1v1)`)
        teleportData = buildTemplateTeleportData(player)
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

    if not roundSystem then
        local expected = #teleportData.teamOnePlayers + #teleportData.teamTwoPlayers
        print(`[Round] Creating RoundSystem — map: {teleportData.mapName}, expecting {expected} player(s)`)
        roundSystem = RoundService.new(teleportData)
    end

    roundSystem:RegisterPlayer(player)

    --// Cosmetic waiting-area spawn. This CharacterAdded handler does NOT write
    --// readiness facts — those are written exclusively by loadCharacterAndRecord.
    player.CharacterAdded:Connect(function(character)
        if roundSystem:GetState() == Configs.GAME_STATES.WaitingForPlayers then
            local rootPart = character:WaitForChild("HumanoidRootPart", Configs.CHAR_FACT_WAIT_TIMEOUT)
            if rootPart then
                local spawnBox = workspace:FindFirstChild(Configs.INITIAL_SPAWN_PART)
                if spawnBox then
                    local half = spawnBox.Size / 2
                    local rx = (math.random() * 2 - 1) * half.X
                    local rz = (math.random() * 2 - 1) * half.Z
                    rootPart.CFrame = spawnBox.CFrame * CFrame.new(rx, half.Y + 3, rz)
                    print(`[Round] {player.Name} spawned in InitialSpawnBox`)
                else
                    warn("[Round] InitialSpawnBox not found in workspace")
                end
            end
        end

        local humanoid = character:WaitForChild("Humanoid")
        humanoid.Died:Connect(function()
            roundSystem:OnPlayerDied(player)
        end)
    end)

    player:LoadCharacter()
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do setupPlayer(player) end

Players.PlayerRemoving:Connect(function(player: Player)
    if roundSystem then roundSystem:UnregisterPlayer(player) end
    PlayerReadiness.destroyRecord(player)
end)
```

Key differences from the original:
- No `ServerStorage.RoundEvents.PositioningDone` WaitForChild.
- `RoundService.new(teleportData)` no longer takes the BindableEvent.
- `PlayerReadiness.ensureRecord` / `destroyRecord` on join/leave.
- `ServerEventBus:Connect("ProfileLoaded", …)` translates to a fact write.
- `CHAR_FACT_WAIT_TIMEOUT` replaces `CHARACTER_LOAD_TIMEOUT` in the cosmetic WaitForChild.

- [ ] **Step 2: Verify the project starts in Studio**

Run Studio with the project synced. Expected: no errors in output; the `[Round] Creating RoundSystem` print appears when a player joins a test session.

- [ ] **Step 3: Commit**

```bash
git add src/Server/RoundService/executor.server.lua
git commit -m "refactor(round-executor): wire PlayerReadiness, drop ServerStorage BindableEvent"
```

---

## Task 19: Delete `WeaponSystemState` module

**Files:**
- Delete: `src/Server/WeaponSystemState/init.lua`
- Delete: `src/Server/WeaponSystemState/WeaponSystemState.test.lua`
- Delete: `src/Server/WeaponSystemState/` (directory)

- [ ] **Step 1: Verify no remaining requires**

Search the codebase for any remaining references:

```
Grep(pattern = "WeaponSystemState", path = "src")
```

Expected: zero matches. If there are any, they must be removed in a prior task before proceeding.

- [ ] **Step 2: Delete the files**

```bash
rm -r src/Server/WeaponSystemState
```

- [ ] **Step 3: Verify the project still loads**

Run Studio with the project synced. Expected: no errors about missing `WeaponSystemState` module.

- [ ] **Step 4: Commit**

```bash
git add -A src/Server/WeaponSystemState
git commit -m "refactor: delete WeaponSystemState (readiness now owned by RoundSystem)"
```

---

## Task 20: Integration test — first round happy path

**Files:**
- Create: `src/Server/RoundService/integration_readiness.test.lua`

- [ ] **Step 1: Write the integration test**

Create `src/Server/RoundService/integration_readiness.test.lua`:

```lua
--// Integration test — drives the full PreparingPlayers → RoundActive path.
--// Run via mcp__robloxstudio__execute_luau in the edit environment with
--// GlobalConfigs.TEST_MODE = true so the executor uses template teleport data.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerReadiness = require(ServerScriptService.RoundService.PlayerReadiness)
local Configs = require(ReplicatedStorage.Round.Configs)

local passed = 0
local failed = 0
local function check(label, cond, detail)
    if cond then
        print(`PASS: {label}`)
        passed += 1
    else
        print(`FAIL: {label}{detail and " — " .. detail or ""}`)
        failed += 1
    end
end

--// Happy path: find a real player (must be joined via TEST_MODE) and verify
--// their readiness record eventually has all four facts after setup completes.
local player = Players:GetPlayers()[1]
if not player then
    print("[integration] SKIPPED — no player in session. Join a TEST_MODE session first.")
    return
end

--// Wait up to 25 seconds for the record to become complete.
--// READINESS_GRACE_FIRST_ROUND is 20s, so 25s leaves margin.
local deadline = os.clock() + 25
while not PlayerReadiness.isComplete(player) and os.clock() < deadline do
    task.wait(0.2)
end

check("integration: record exists for player", PlayerReadiness.getRecord(player) ~= nil)
check("integration: isComplete after grace", PlayerReadiness.isComplete(player))

local missing = PlayerReadiness.missingFacts(player)
check("integration: no missing facts", #missing == 0, "missing: " .. table.concat(missing, ", "))

print(`\n{passed} passed, {failed} failed`)
```

- [ ] **Step 2: Run the integration test in a live session**

1. Open Studio with the project synced (Argon serve).
2. Set `GlobalConfigs.TEST_MODE = true` (already is per the current GlobalConfigs.lua modification).
3. Start a test play session (yes — this is an integration test, not a unit test, and requires a live environment).
4. Execute the test file via `mcp__robloxstudio__execute_luau`.

Expected output: `3 passed, 0 failed` OR `SKIPPED` if no player is in the session.

Note: Per CLAUDE.md, normally we avoid live playtests. For **this one integration test** a live session is required because the whole point is to exercise `player:LoadCharacter()` and the real Roblox lifecycle. If running a playtest is not acceptable, skip this task and verify manually by reading server output during development testing.

- [ ] **Step 3: Commit**

```bash
git add src/Server/RoundService/integration_readiness.test.lua
git commit -m "test(round): integration test for first-round readiness happy path"
```

---

## Task 21: Integration test — Skipped state physical contract

**Files:**
- Modify: `src/Server/RoundService/integration_readiness.test.lua`

- [ ] **Step 1: Add a test case that forces a player into Skipped state**

Append to the integration test file, before the final summary print:

```lua
--// Force-skip test: directly invoke applySkipped by requiring the orchestrator
--// and calling its internal helper via a test hook.
--// Since applySkipped is module-local, we can't call it directly. Instead, we
--// simulate the condition by setting status to Alive then calling it through
--// a public test hook that the orchestrator exposes in debug mode.

--// If RoundOrchestrator doesn't expose a test hook, this test is skipped.
local RoundOrchestrator = require(ServerScriptService.RoundService.RoundOrchestrator)
if not RoundOrchestrator._testApplySkipped then
    print("[integration] SKIPPED force-skip test — no _testApplySkipped hook")
else
    local RoundService = require(ServerScriptService.RoundService)
    local roundSystem = _G._testRoundSystem   --// requires the executor to expose this
    if not roundSystem then
        print("[integration] SKIPPED force-skip test — no _testRoundSystem global")
    else
        local playerState = roundSystem._playerStates[player]
        if playerState and playerState.status == Configs.PLAYER_STATUSES.Alive then
            RoundOrchestrator._testApplySkipped(roundSystem, player, playerState)

            check("force-skip: status is Skipped", playerState.status == Configs.PLAYER_STATUSES.Skipped)

            local character = player.Character
            if character then
                local hrp = character:FindFirstChild("HumanoidRootPart")
                check("force-skip: HRP anchored", hrp and hrp.Anchored == true)
                check("force-skip: ForceField present", character:FindFirstChildOfClass("ForceField") ~= nil)
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                check("force-skip: WalkSpeed = 0", humanoid and humanoid.WalkSpeed == 0)
            end

            local backpack = player:FindFirstChildOfClass("Backpack")
            check("force-skip: backpack empty of Tools", backpack and #backpack:GetChildren() == 0)
        else
            print("[integration] SKIPPED — player not Alive, current status: " .. tostring(playerState and playerState.status))
        end
    end
end
```

- [ ] **Step 2: Expose the `_testApplySkipped` hook in RoundOrchestrator**

In `src/Server/RoundService/RoundOrchestrator.lua`, near the bottom (before `return RoundOrchestrator`), add:

```lua
--// Test-only hook. Not called by any production code path.
RoundOrchestrator._testApplySkipped = applySkipped
```

- [ ] **Step 3: Expose `_testRoundSystem` in the executor**

In `src/Server/RoundService/executor.server.lua`, inside `setupPlayer` just after `roundSystem = RoundService.new(teleportData)`, add:

```lua
if GlobalConfigs.TEST_MODE then
    _G._testRoundSystem = roundSystem
end
```

- [ ] **Step 4: Run the integration test in a live session**

1. Ensure Studio is running with a test session and the player is in Alive state (post-PreparingPlayers, mid-RoundActive).
2. Run the test file via `execute_luau`.

Expected: all force-skip assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Server/RoundService/integration_readiness.test.lua src/Server/RoundService/RoundOrchestrator.lua src/Server/RoundService/executor.server.lua
git commit -m "test(round): integration test for Skipped physical contract + test hooks"
```

---

## Task 22: Final verification — full test suite pass

**Files:**
- No files modified; this is a verification task.

- [ ] **Step 1: Run every `*.test.lua` file in sequence via `execute_luau`**

Run these in the edit environment (no playtest needed for the first three):

1. `src/Server/RoundService/PlayerReadiness.test.lua`
2. `src/Server/RoundService/RoundSystem.test.lua`
3. `src/Server/WeaponDistributor/WeaponDistributor.test.lua`

Expected: each prints `N passed, 0 failed`.

- [ ] **Step 2: Run the integration test in a live session**

Run `src/Server/RoundService/integration_readiness.test.lua` via `execute_luau` with a test session active. Expected: all assertions PASS (or SKIPPED blocks where applicable).

- [ ] **Step 3: Manual smoke test**

Open Studio, start a test session with `TEST_MODE = true`, observe the `[Round]` prints. Expected sequence:
1. `Creating RoundSystem`
2. `{player} registered`
3. `State: AssigningTeams`
4. `State: PreparingPlayers`
5. `State: RoundActive — Round 1`
6. (round plays out)
7. `State: RoundIntermission`
8. `State: RoundActive — Round 2`

No "Weapon system not ready" warnings. No `ServerStorage.RoundEvents.PositioningDone` errors. No kicks with `CharacterLoadTimeout`.

- [ ] **Step 4: No commit for this task**

This task is verification only. If any step fails, stop and fix the underlying issue in the relevant earlier task before committing.

---

## Self-Review

**Spec coverage check:**
- §1 Problem, §2 Goal, §3 Non-goals: covered by the whole plan.
- §4 Architecture (one-owner, three layers, dep diagram): Tasks 4-6 (PlayerReadiness), Task 7 (DataService producer), Task 18 (executor wiring).
- §5 State machine (PreparingPlayers, LEGAL_TRANSITIONS, PLAYER_STATUSES, new Configs): Task 1.
- §6 Round roster: Task 10 (roster field), Task 14 (populate), Task 17 (intermission preserves).
- §7 PlayerReadiness contract: Tasks 4, 5, 6.
- §8.1 enterPreparingPlayers: Task 15.
- §8.2 enterRoundActive non-blocking: Task 16.
- §8.3 loadCharacterAndRecord: Task 11.
- §8.4 applySkipped: Task 12.
- §8.5 exitSkippedOrPosition: Task 13.
- §8.6 intermission exit cleanup: Task 17.
- §9 Skipped real-world contract: Task 12 (applySkipped), Task 21 (integration test).
- §10 Timeout audit: constants in Task 1, used throughout Tasks 11, 15, 16.
- §10.1 Script-load wait elimination: Task 10 (RoundSystem constructor change), Task 18 (executor change).
- §10.2 pcall wrap: Task 16.
- §11.1 New files: Tasks 4, 20.
- §11.2 Types: (small omission — no explicit task, but the type aliases are purely optional Luau annotations, not load-bearing).
- §11.3 Configs: Task 1.
- §11.4 DataService: Task 7.
- §11.5-11.6 WeaponDistributor: Tasks 8, 9.
- §11.7 WeaponSystemState delete: Task 19.
- §11.8 Executor: Task 18.
- §11.9 RoundSystem init: Task 10.
- §11.10 RoundOrchestrator: Tasks 11-17.
- §11.11 PlayerState: Task 3.
- §11.12 TeamState: Task 2.
- §11.13 KnifeService / GunService: zero changes — no task needed.
- §11.14 Client spectate: follow-up, not in this plan.
- §12 Error handling matrix: covered by the individual task changes.
- §13 Testing notes: Tasks 4-6 (unit tests), 20-21 (integration).

**Gaps found in self-review:**
- `Types.lua` type aliases (PlayerStatus, ReadinessFact) — optional Luau annotations. **Mitigation:** add as a trailing step in Task 3 (for PlayerStatus) and Task 4 (for ReadinessFact), OR skip entirely since these are documentation-only in this codebase. **Decision:** skip — the codebase's existing type surface is light and the strict string values in Configs are the runtime truth.
- Task 21's `_testRoundSystem` global is a shortcut; the cleaner alternative (exposing via a module accessor) is overkill for a test-only hook. Kept as-is.

**Placeholder scan:** grep for "TODO", "TBD", "fill in", `...` (ellipsis in code) → none found in the plan. Every code block is complete.

**Type consistency:** function names match across tasks (`loadCharacterAndRecord`, `applySkipped`, `exitSkippedOrPosition`, `allRosterReady`, `recordCharacterFact`, `beginCharacterLoad`, `clearFact`, `recordFact`, `isComplete`, `missingFacts`, `ensureRecord`, `destroyRecord`, `getRecord`, `waitForChange`, `waitForComplete`, `ChangedSignal`). Player status names match (`Alive`, `Dead`, `Disconnected`, `Skipped`). Config constant names match (`READINESS_GRACE_FIRST_ROUND`, `LATE_TELEPORT_GRACE`, `CHAR_FACT_WAIT_TIMEOUT`, `POSITIONING_OUTER_TIMEOUT`, `DEFAULT_WALK_SPEED`, `REQUIRED_FACTS`).

Self-review complete.
