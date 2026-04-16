# Spectate System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a client-only spectate system that derives all session state from the existing `RoundUpdate` snapshot broadcast — no new server code, no new remotes.

**Architecture:** Pure derivation module in `src/Shared/Spectate/` computes `SpectateClientState` from `(snapshot, localUserId, prevTargetUserId)`. Stateful `SpectateController` in `src/Client/SpectateController/` subscribes to `ClientEventBus:Connect("RoundUpdate")`, calls the pure derive function, and applies camera side effects with full `Character`/`Humanoid` validation. Every failure path restores camera to self, clears target, warns — never silent.

**Tech Stack:** Roblox Luau, Rojo/Argon sync, `mcp__robloxstudio__execute_luau` for integration tests.

**Spec:** `docs/superpowers/specs/2026-04-16-spectate-system-design.md`

---

## File Structure

**Create:**
- `src/Shared/Spectate/Types.lua` — exports `SpectateClientState`
- `src/Shared/Spectate/derive.lua` — pure derivation, snapshot validation
- `src/Shared/Spectate/derive.test.lua` — integration tests for derivation
- `src/Client/SpectateController/init.lua` — stateful controller, camera side effects, public API
- `src/Client/SpectateController/Configs.lua` — input keys
- `src/Client/SpectateController/executor.client.lua` — bootstrap; subscribes to `ClientEventBus`, wires input

**Modify:** none. The server already broadcasts everything needed via `RoundUpdate` in `src/Server/RoundService/init.lua`.

---

## Project Testing Conventions (read first)

- **Integration tests only.** No unit tests. Feed real inputs, assert on derived output shape.
- Test files live next to the module they cover: `<Module>.test.lua`.
- Tests are executed from Studio's command bar via `mcp__robloxstudio__execute_luau`, which loads the module via `require(ReplicatedStorage.<path>)` or `require(ServerScriptService.<path>)`.
- Test format: self-contained script printing `PASS: <label>` / `FAIL: <label> — <detail>` via a `check(label, cond, detail?)` helper. See `src/Server/RoundService/RoundSystem.test.lua` for the canonical pattern.
- Mock players are plain tables: `{ Name = "X", UserId = 1 }`. No `Instance.new` for anything.
- `warn` on failure paths is mandatory. `assert` is banned. No silent returns.
- Comments use `--//`.

---

### Task 1: `SpectateClientState` type

**Files:**
- Create: `src/Shared/Spectate/Types.lua`

- [ ] **Step 1: Write the type module**

```lua
--// src/Shared/Spectate/Types.lua
--// Data contract for client-derived spectate state.

export type PlayerEntry = {
	team: number,
	isInGame: boolean,
	isEliminated: boolean,
}

export type SpectateClientState = {
	isRoundActive: boolean,
	selfInGame: boolean,
	selfEliminated: boolean,
	players: { [number]: PlayerEntry },
	canSpectate: boolean,
	availableTargets: { number },        --// teammates first (asc userId), then opponents (asc userId)
	currentTargetUserId: number?,
	isSpectating: boolean,
}

return {}
```

- [ ] **Step 2: Commit**

```bash
git add src/Shared/Spectate/Types.lua
git commit -m "feat(spectate): add SpectateClientState type"
```

---

### Task 2: Failing tests for `derive.lua`

**Files:**
- Create: `src/Shared/Spectate/derive.test.lua`

- [ ] **Step 1: Write the test harness**

```lua
--// src/Shared/Spectate/derive.test.lua
--// Integration tests for pure spectate derivation.
--// Run via mcp__robloxstudio__execute_luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local derive = require(ReplicatedStorage.Spectate.derive)

local passed = 0
local failed = 0

local function check(label: string, cond: boolean, detail: string?)
	if cond then
		print(`PASS: {label}`)
		passed += 1
	else
		print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
		failed += 1
	end
end

local function mockPlayer(userId: number)
	return { Name = `P{userId}`, UserId = userId }
end

local function entry(userId: number, team: number, status: string, isInGame: boolean)
	return {
		player = mockPlayer(userId),
		team = team,
		status = status,
		isInGame = isInGame,
	}
end

--// ── Round not active ────────────────────────────────────────────────────────
do
	local snap = {
		state = "WaitingForPlayers",
		playerStates = { entry(1, 1, "Alive", true), entry(2, 2, "Alive", true) },
	}
	local s = derive(snap, 1, nil)
	check("RoundNotActive: canSpectate=false", s.canSpectate == false)
	check("RoundNotActive: currentTargetUserId=nil", s.currentTargetUserId == nil)
	check("RoundNotActive: isSpectating=false", s.isSpectating == false)
end

--// ── Round active, self alive+inGame ────────────────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = { entry(1, 1, "Alive", true), entry(2, 2, "Alive", true) },
	}
	local s = derive(snap, 1, nil)
	check("SelfAliveInGame: canSpectate=false", s.canSpectate == false)
	check("SelfAliveInGame: currentTargetUserId=nil", s.currentTargetUserId == nil)
end

--// ── Round active, self dead ────────────────────────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			entry(1, 1, "Dead", true),
			entry(2, 2, "Alive", true),
			entry(3, 2, "Dead", true),
			entry(4, 1, "Disconnected", false),
			entry(5, 2, "Skipped", false),
		},
	}
	local s = derive(snap, 1, nil)
	check("SelfDead: canSpectate=true", s.canSpectate == true)
	check("SelfDead: availableTargets excludes self/dead/disconnected/skipped",
		#s.availableTargets == 1 and s.availableTargets[1] == 2)
	check("SelfDead: isSpectating=true", s.isSpectating == true)
	check("SelfDead: currentTargetUserId=2", s.currentTargetUserId == 2)
end

--// ── Round active, self Skipped (not in game) ───────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			entry(1, 1, "Skipped", false),
			entry(2, 2, "Alive", true),
		},
	}
	local s = derive(snap, 1, nil)
	check("SelfSkipped: canSpectate=true", s.canSpectate == true)
end

--// ── Prev target still valid ────────────────────────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			entry(1, 1, "Dead", true),
			entry(2, 2, "Alive", true),
			entry(3, 2, "Alive", true),
		},
	}
	local s = derive(snap, 1, 3)
	check("PrevValid: retained", s.currentTargetUserId == 3)
end

--// ── Prev target invalidated ────────────────────────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			entry(1, 1, "Dead", true),
			entry(2, 2, "Alive", true),
			entry(3, 2, "Dead", true),
		},
	}
	local s = derive(snap, 1, 3)
	check("PrevInvalid: falls to first available", s.currentTargetUserId == 2)
end

--// ── All targets gone ───────────────────────────────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			entry(1, 1, "Dead", true),
			entry(2, 2, "Dead", true),
		},
	}
	local s = derive(snap, 1, 2)
	check("NoTargets: currentTargetUserId=nil", s.currentTargetUserId == nil)
	check("NoTargets: isSpectating=false", s.isSpectating == false)
	check("NoTargets: availableTargets empty", #s.availableTargets == 0)
end

--// ── Local user absent from snapshot (fail closed) ─────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = { entry(2, 2, "Alive", true) },
	}
	local s = derive(snap, 99, nil)
	check("SelfAbsent: canSpectate=false", s.canSpectate == false)
	check("SelfAbsent: availableTargets empty", #s.availableTargets == 0)
	check("SelfAbsent: currentTargetUserId=nil", s.currentTargetUserId == nil)
end

--// ── Malformed snapshot: not a table ───────────────────────────────────────
do
	local s = derive(nil, 1, nil)
	check("Malformed(nil): canSpectate=false", s.canSpectate == false)
	check("Malformed(nil): isSpectating=false", s.isSpectating == false)
end

--// ── Malformed snapshot: missing state ─────────────────────────────────────
do
	local s = derive({ playerStates = {} }, 1, nil)
	check("Malformed(no state): canSpectate=false", s.canSpectate == false)
end

--// ── Malformed snapshot: missing playerStates ──────────────────────────────
do
	local s = derive({ state = "RoundActive" }, 1, nil)
	check("Malformed(no playerStates): canSpectate=false", s.canSpectate == false)
end

--// ── Malformed snapshot: entry missing team ────────────────────────────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			{ player = mockPlayer(1), status = "Dead", isInGame = true },  --// no team
		},
	}
	local s = derive(snap, 1, nil)
	check("Malformed(no team): canSpectate=false", s.canSpectate == false)
end

--// ── Target ordering: teammates first, then opponents, asc within ──────────
do
	local snap = {
		state = "RoundActive",
		playerStates = {
			entry(100, 1, "Dead", true),   --// self
			entry(103, 1, "Alive", true),  --// teammate
			entry(101, 1, "Alive", true),  --// teammate
			entry(104, 2, "Alive", true),  --// opponent
			entry(102, 2, "Alive", true),  --// opponent
		},
	}
	local s = derive(snap, 100, nil)
	check(
		"Ordering: teammates first asc, then opponents asc",
		#s.availableTargets == 4
			and s.availableTargets[1] == 101
			and s.availableTargets[2] == 103
			and s.availableTargets[3] == 102
			and s.availableTargets[4] == 104,
		`got {table.concat(s.availableTargets, ",")}`
	)
end

print(`\n── derive.test ──  passed: {passed}  failed: {failed} ──`)
```

- [ ] **Step 2: Run and verify FAIL**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Spectate["derive.test"])
```

Expected: Error — `ReplicatedStorage.Spectate` does not yet exist. That's the expected failing state before Task 3.

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Spectate/derive.test.lua
git commit -m "test(spectate): integration tests for derive"
```

---

### Task 3: Implement `derive.lua`

**Files:**
- Create: `src/Shared/Spectate/derive.lua`

- [ ] **Step 1: Write the pure derivation**

```lua
--// src/Shared/Spectate/derive.lua
--// Pure derivation from RoundUpdate snapshot to SpectateClientState.
--// No callbacks, no signals, no Roblox API calls beyond `warn`.

local Types = require(script.Parent.Types)
export type SpectateClientState = Types.SpectateClientState

local ROUND_ACTIVE = "RoundActive"
local STATUS_DEAD = "Dead"

local function emptyState(): SpectateClientState
	return {
		isRoundActive = false,
		selfInGame = false,
		selfEliminated = false,
		players = {},
		canSpectate = false,
		availableTargets = {},
		currentTargetUserId = nil,
		isSpectating = false,
	}
end

local function validateEntry(entry: any): boolean
	if type(entry) ~= "table" then return false end
	if type(entry.player) ~= "table" then return false end
	if type(entry.player.UserId) ~= "number" then return false end
	if type(entry.team) ~= "number" then return false end
	if type(entry.status) ~= "string" then return false end
	if type(entry.isInGame) ~= "boolean" then return false end
	return true
end

local function validateSnapshot(snapshot: any): boolean
	if type(snapshot) ~= "table" then
		warn("[Spectate.derive] snapshot is not a table")
		return false
	end
	if type(snapshot.state) ~= "string" then
		warn("[Spectate.derive] snapshot.state missing or not a string")
		return false
	end
	if type(snapshot.playerStates) ~= "table" then
		warn("[Spectate.derive] snapshot.playerStates missing or not a table")
		return false
	end
	for i, entry in snapshot.playerStates do
		if not validateEntry(entry) then
			warn(`[Spectate.derive] snapshot.playerStates[{i}] failed shape validation`)
			return false
		end
	end
	return true
end

local function derive(snapshot: any, localUserId: number, prevTargetUserId: number?): SpectateClientState
	if not validateSnapshot(snapshot) then
		return emptyState()
	end

	local isRoundActive = snapshot.state == ROUND_ACTIVE

	local players: { [number]: Types.PlayerEntry } = {}
	for _, entry in snapshot.playerStates do
		players[entry.player.UserId] = {
			team = entry.team,
			isInGame = entry.isInGame,
			isEliminated = entry.status == STATUS_DEAD,
		}
	end

	local selfEntry = players[localUserId]
	if selfEntry == nil then
		warn(`[Spectate.derive] local user {localUserId} absent from snapshot; failing closed`)
		local s = emptyState()
		s.isRoundActive = isRoundActive
		s.players = players
		return s
	end

	local selfInGame = selfEntry.isInGame
	local selfEliminated = selfEntry.isEliminated
	local selfTeam = selfEntry.team
	local canSpectate = isRoundActive and (selfEliminated or not selfInGame)

	--// Build availableTargets: teammates asc, then opponents asc.
	local teammates: { number } = {}
	local opponents: { number } = {}
	for userId, p in players do
		if userId == localUserId then continue end
		if not (p.isInGame and not p.isEliminated) then continue end
		if p.team == selfTeam then
			table.insert(teammates, userId)
		else
			table.insert(opponents, userId)
		end
	end
	table.sort(teammates)
	table.sort(opponents)

	local availableTargets: { number } = {}
	for _, id in teammates do table.insert(availableTargets, id) end
	for _, id in opponents do table.insert(availableTargets, id) end

	--// Target resolution.
	local currentTargetUserId: number? = nil
	if prevTargetUserId ~= nil and table.find(availableTargets, prevTargetUserId) then
		currentTargetUserId = prevTargetUserId
	elseif #availableTargets > 0 then
		currentTargetUserId = availableTargets[1]
	end

	if not canSpectate then
		currentTargetUserId = nil
	end

	local isSpectating = canSpectate and currentTargetUserId ~= nil

	return {
		isRoundActive = isRoundActive,
		selfInGame = selfInGame,
		selfEliminated = selfEliminated,
		players = players,
		canSpectate = canSpectate,
		availableTargets = availableTargets,
		currentTargetUserId = currentTargetUserId,
		isSpectating = isSpectating,
	}
end

return derive
```

- [ ] **Step 2: Run tests and verify PASS**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Spectate["derive.test"])
```

Expected output:
```
PASS: RoundNotActive: canSpectate=false
PASS: RoundNotActive: currentTargetUserId=nil
...
── derive.test ──  passed: 24  failed: 0 ──
```

If any FAIL lines appear, fix `derive.lua` (NOT the test) until the asserted behavior holds, then re-run.

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Spectate/derive.lua
git commit -m "feat(spectate): pure derivation of SpectateClientState"
```

---

### Task 4: Configs

**Files:**
- Create: `src/Client/SpectateController/Configs.lua`

- [ ] **Step 1: Write configs**

```lua
--// src/Client/SpectateController/Configs.lua
--// Config-only; no magic values elsewhere in the controller.

return {
	INPUT_NEXT_TARGET = Enum.KeyCode.E,
	INPUT_PREVIOUS_TARGET = Enum.KeyCode.Q,
	INPUT_CLEAR_TARGET = Enum.KeyCode.X,
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Client/SpectateController/Configs.lua
git commit -m "feat(spectate): input keycode configs"
```

---

### Task 5: Stateful `SpectateController`

**Files:**
- Create: `src/Client/SpectateController/init.lua`

- [ ] **Step 1: Write the controller**

```lua
--// src/Client/SpectateController/init.lua
--// Stateful controller; owns SpectateClientState and camera side effects.
--// derive.lua is pure; this file handles everything that touches Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local derive = require(ReplicatedStorage.Spectate.derive)
local Types = require(ReplicatedStorage.Spectate.Types)

export type SpectateClientState = Types.SpectateClientState

local SpectateController = {}

local initialized = false
local camera: Camera? = nil
local localPlayer: Player? = nil
local state: SpectateClientState = {
	isRoundActive = false,
	selfInGame = false,
	selfEliminated = false,
	players = {},
	canSpectate = false,
	availableTargets = {},
	currentTargetUserId = nil,
	isSpectating = false,
}

local function getLocalHumanoid(): Humanoid?
	if not localPlayer then return nil end
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function restoreCameraToSelf()
	if not camera then return end
	camera.CameraSubject = getLocalHumanoid()  --// nil is valid
end

local function applyCamera()
	if not camera then return end
	if not state.isSpectating or state.currentTargetUserId == nil then
		restoreCameraToSelf()
		return
	end

	local target = Players:GetPlayerByUserId(state.currentTargetUserId)
	if not target then
		warn(`[Spectate] target userId {state.currentTargetUserId} resolves to no Player; clearing`)
		state.currentTargetUserId = nil
		state.isSpectating = false
		restoreCameraToSelf()
		return
	end

	local char = target.Character
	if not char then
		warn(`[Spectate] target {target.Name} has no Character yet; clearing`)
		state.currentTargetUserId = nil
		state.isSpectating = false
		restoreCameraToSelf()
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[Spectate] target {target.Name} has no Humanoid; clearing`)
		state.currentTargetUserId = nil
		state.isSpectating = false
		restoreCameraToSelf()
		return
	end

	camera.CameraSubject = humanoid
end

function SpectateController.Init(injectedCamera: Camera?, injectedLocalPlayer: Player?)
	if initialized then
		warn("[Spectate] Init called twice; ignoring")
		return
	end
	initialized = true
	camera = injectedCamera
	localPlayer = injectedLocalPlayer or Players.LocalPlayer
end

function SpectateController.HandleRoundUpdate(snapshot: any)
	if not localPlayer then
		warn("[Spectate] HandleRoundUpdate called before Init")
		return
	end
	state = derive(snapshot, localPlayer.UserId, state.currentTargetUserId)
	applyCamera()
end

function SpectateController.GetState(): SpectateClientState
	return state
end

function SpectateController.SelectTarget(userId: number)
	if not table.find(state.availableTargets, userId) then
		warn(`[Spectate] SelectTarget({userId}): userId not in availableTargets; ignoring`)
		return
	end
	if not state.canSpectate then
		warn("[Spectate] SelectTarget called while canSpectate=false; ignoring")
		return
	end
	state.currentTargetUserId = userId
	state.isSpectating = true
	applyCamera()
end

local function cycle(delta: number)
	if not state.canSpectate then
		warn("[Spectate] cycle called while canSpectate=false; ignoring")
		return
	end
	local list = state.availableTargets
	if #list == 0 then
		warn("[Spectate] cycle called with no availableTargets; ignoring")
		return
	end
	local currentIdx = state.currentTargetUserId and table.find(list, state.currentTargetUserId) or 0
	local nextIdx = ((currentIdx - 1 + delta) % #list) + 1
	state.currentTargetUserId = list[nextIdx]
	state.isSpectating = true
	applyCamera()
end

function SpectateController.SelectNext()
	cycle(1)
end

function SpectateController.SelectPrevious()
	cycle(-1)
end

function SpectateController.Clear()
	state.currentTargetUserId = nil
	state.isSpectating = false
	restoreCameraToSelf()
end

return SpectateController
```

- [ ] **Step 2: Verify module loads cleanly**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local StarterPlayerScripts = game:GetService("StarterPlayer").StarterPlayerScripts
local SpectateController = require(StarterPlayerScripts.SpectateController)
SpectateController.Init(nil, nil)  --// nil-safe per CLAUDE.md convention
SpectateController.HandleRoundUpdate({ state = "WaitingForPlayers", playerStates = {} })
local s = SpectateController.GetState()
print("canSpectate:", s.canSpectate, " (expected false)")
print("isSpectating:", s.isSpectating, " (expected false)")
```

Expected: prints `canSpectate: false` and `isSpectating: false`. No errors. A `warn` about `HandleRoundUpdate called before Init` should NOT appear (we called Init first). A `warn` about `local user X absent from snapshot` IS expected — `localPlayer.UserId` is not in the empty snapshot.

- [ ] **Step 3: Commit**

```bash
git add src/Client/SpectateController/init.lua
git commit -m "feat(spectate): stateful controller with camera side effects"
```

---

### Task 6: Executor bootstrap

**Files:**
- Create: `src/Client/SpectateController/executor.client.lua`

- [ ] **Step 1: Write the executor**

```lua
--// src/Client/SpectateController/executor.client.lua
--// Bootstrap: inject Camera + LocalPlayer, subscribe to RoundUpdate,
--// bind input keys. Runs automatically as a LocalScript via Rojo.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local SpectateController = require(script.Parent)
local Configs = require(script.Parent.Configs)
local ClientEventBus = require(script.Parent.Parent.ClientEventBus)

local camera = Workspace.CurrentCamera
if not camera then
	warn("[Spectate] Workspace.CurrentCamera missing at bootstrap; spectate camera will be nil")
end

SpectateController.Init(camera, Players.LocalPlayer)

ClientEventBus:Connect("RoundUpdate", function(snapshot)
	SpectateController.HandleRoundUpdate(snapshot)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == Configs.INPUT_NEXT_TARGET then
		SpectateController.SelectNext()
	elseif input.KeyCode == Configs.INPUT_PREVIOUS_TARGET then
		SpectateController.SelectPrevious()
	elseif input.KeyCode == Configs.INPUT_CLEAR_TARGET then
		SpectateController.Clear()
	end
end)
```

- [ ] **Step 2: Verify Rojo picks up the folder**

After `argon serve` is running (or after `argon build`), verify in Studio that:
- `StarterPlayer.StarterPlayerScripts.SpectateController` exists as a `Folder`
- Inside it: `init` (ModuleScript), `Configs` (ModuleScript), `executor` (LocalScript)
- `ReplicatedStorage.Spectate.derive` and `ReplicatedStorage.Spectate.Types` exist as ModuleScripts
- `ReplicatedStorage.Spectate["derive.test"]` exists as a ModuleScript

If any piece is missing, check `default.project.json` or Argon output — the Rojo mapping `src/Shared → ReplicatedStorage` and `src/Client → StarterPlayer/StarterPlayerScripts` should already be in place (see CLAUDE.md).

- [ ] **Step 3: Commit**

```bash
git add src/Client/SpectateController/executor.client.lua
git commit -m "feat(spectate): executor bootstrap — inject camera, wire input"
```

---

### Task 7: End-to-end smoke test in Studio

This task verifies the full loop works in a real Studio edit session. No new files.

- [ ] **Step 1: Ensure Argon is syncing**

From a terminal: `argon serve` (keep running).

- [ ] **Step 2: Drive a snapshot manually via `execute_luau`**

Execute:

```lua
local ClientEventBus = require(game:GetService("StarterPlayer").StarterPlayerScripts.ClientEventBus)
local SpectateController = require(game:GetService("StarterPlayer").StarterPlayerScripts.SpectateController)
local Players = game:GetService("Players")

--// Fake snapshot: self (LocalPlayer) dead on team 1, one alive opponent on team 2.
local me = Players.LocalPlayer
if not me then
	warn("no LocalPlayer in this context; run this during a Play Solo session")
	return
end

local fakeOpponent = { Name = "Enemy", UserId = 999 }
local snap = {
	state = "RoundActive",
	playerStates = {
		{ player = me, team = 1, status = "Dead", isInGame = true },
		{ player = fakeOpponent, team = 2, status = "Alive", isInGame = true },
	},
}
ClientEventBus:Fire("RoundUpdate", snap)

local s = SpectateController.GetState()
print("canSpectate:", s.canSpectate, "(expected true)")
print("availableTargets:", table.concat(s.availableTargets, ","), "(expected 999)")
print("isSpectating:", s.isSpectating, "(expected true; but camera will warn — 999 has no Player)")
```

Expected: `canSpectate: true`, `availableTargets: 999`, plus a `[Spectate] target userId 999 resolves to no Player; clearing` warn — the controller correctly fails closed for a fabricated opponent. The important verification is that the derive → controller → camera path runs end-to-end without exceptions.

- [ ] **Step 3: (Optional) Real-round verification**

If you have a private-server match setup, run a real round, die, and confirm the camera snaps to an alive teammate/opponent in the expected team order. Press the next/prev/clear keys from `Configs.lua` and confirm camera cycles as expected.

- [ ] **Step 4: No code changes — no commit**

If the smoke test surfaces a bug, return to the relevant task and fix before finalizing.

---

## Done When

- `src/Shared/Spectate/derive.test.lua` passes (0 FAIL lines).
- `src/Client/SpectateController/` exists with `init.lua`, `Configs.lua`, `executor.client.lua`.
- `SpectateController.HandleRoundUpdate` runs without exceptions given a `RoundUpdate` snapshot.
- Camera targets validate `Player` → `Character` → `Humanoid` in that order; any missing link clears target, restores camera, warns.
- `availableTargets` order: teammates asc, then opponents asc.
- No new server code, no new remotes, no modifications to `src/Server/`.
- Every commit compiles cleanly (Rojo sync does not error).
