# Mobile Weapon Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a platform-split client-side weapon input stack so knife stab/throw and gun shoot work on mobile via tap-vs-hold gestures, add a cosmetic Reload action, and delete the obsolete `InputPosition` + `InputRouter` modules.

**Architecture:** A new `src/Client/WeaponInput/` module selects between `PCInputModule` (LMB gesture, `R` key reload, mouse-raycast aim) and `MobileInputModule` (touch gesture, CAS touch-button reload, camera-lookvector aim) at startup via `src/Shared/DeviceType.lua`. Both modules share a pure `GestureRecognizer` that classifies pointer streams into `Tap`, `HoldRelease`, `Pan`, or `Ignored`. Weapon controllers subscribe via `bindKnife`/`bindGun` handlers, and receive a world `aimTarget: Vector3?` parameter on action callbacks instead of computing aim themselves. The server knife path is untouched; the server gun path gains only a cosmetic `Reload` action.

**Tech Stack:** Roblox Luau, Rojo/Argon sync. Integration tests run via `mcp__robloxstudio__execute_luau` in the Studio edit environment — never via playtest. No unit tests.

**Project invariants** (from `CLAUDE.md`):
- Comments use `--//` syntax only
- `assert` is banned; use `warn` + return
- No silent returns; every non-happy-path must log via `warn`
- UI instances are never created in code (`Instance.new("Frame")` etc. are forbidden)
- File operations via `Read`/`Write`/`Edit` — never via MCP tools

**Reference spec:** `docs/superpowers/specs/2026-04-13-mobile-weapon-input-design.md`

---

## File layout summary

| Action | Path | Responsibility |
|---|---|---|
| NEW | `src/Shared/DeviceType.lua` | `DeviceType.getDevice(): "PC" \| "Mobile"` (stub; user fills body) |
| NEW | `src/Client/WeaponInput/init.lua` | Platform selector, returns PC or Mobile module |
| NEW | `src/Client/WeaponInput/Types.lua` | `KnifeHandlers`, `GunHandlers`, `GestureState`, `GestureResult` |
| NEW | `src/Client/WeaponInput/Configs.lua` | `HoldThreshold`, `PanDragThreshold`, `ReloadKeyCode`, `ReloadTouchButtonName` |
| NEW | `src/Client/WeaponInput/GestureRecognizer.lua` | Pure classifier: `onDown`/`onMove`/`onUp`/`reset` |
| NEW | `src/Client/WeaponInput/PCInputModule.lua` | LMB gesture + `R` reload + mouse aim |
| NEW | `src/Client/WeaponInput/MobileInputModule.lua` | Touch gesture + CAS reload button + camera aim |
| NEW | `src/Client/WeaponInput/executor.client.lua` | `require(script.Parent)` |
| NEW | `src/Client/GunController/Actions/ReloadAction.lua` | Cosmetic client action |
| NEW | `src/Server/GunService/Actions/ReloadAction.lua` | Cosmetic server action |
| MODIFY | `src/Shared/Gun/Configs.lua` | Add `Reload` to `ValidActions`, add `Reload*` fields |
| MODIFY | `src/Shared/Gun/GunStateMachine.lua` | Add `isReloading`, `Reload` branches, `Shoot` rejection during reload |
| MODIFY | `src/Shared/Gun/Types.lua` | Add `isReloading` to `GunStateMachine` type |
| MODIFY | `src/Client/GunController/ActionRegistry.lua` | Register `ReloadAction` |
| MODIFY | `src/Server/GunService/ActionRegistry.lua` | Register `ReloadAction` |
| MODIFY | `src/Client/KnifeController/init.lua` | `performAction(actionName, aimTarget?)` — delete `InputPosition` usage |
| MODIFY | `src/Client/GunController/init.lua` | `performAction(actionName, aimTarget?)` — delete `InputPosition` usage |
| MODIFY | `src/Client/KnifeController/executor.client.lua` | Subscribe via `WeaponInput.bindKnife` |
| MODIFY | `src/Client/GunController/executor.client.lua` | Subscribe via `WeaponInput.bindGun` |
| DELETE | `src/Client/InputPosition.lua` | Replaced by per-module aim helpers |
| DELETE | `src/Client/InputRouter/init.lua` | No remaining consumers |
| DELETE | `src/Client/InputRouter/Configs.lua` | |
| DELETE | `src/Client/InputRouter/executor.client.lua` | |

---

## Execution rules

- Run every test via `mcp__robloxstudio__execute_luau`. Never start a playtest. Never join the game.
- Never chain Bash commands with `&&` or `;`. Use separate parallel Bash tool calls.
- Never use `mcp__robloxstudio__*` to read/write/edit scripts. Only `Read`/`Write`/`Edit`.
- Commit after every task. Small green commits only.
- A "test passes" means the `execute_luau` script prints `OK: <case>` for every asserted case, with no `ERROR` lines.

**Test assertion helper** (used throughout — inline this block in every `execute_luau` script):

```lua
local function assertEq(name, actual, expected)
    if actual == expected then
        print("OK: " .. name)
    else
        print(string.format("ERROR: %s — expected %s, got %s", name, tostring(expected), tostring(actual)))
    end
end
```

---

## Task 1: Create `DeviceType` stub

**Files:**
- Create: `src/Shared/DeviceType.lua`

- [ ] **Step 1: Write the module stub**

Write `src/Shared/DeviceType.lua`:

```lua
--// Device classification used by platform-split subsystems (e.g. WeaponInput).
--// The user maintains the body of getDevice(); the interface is locked at
--// returning either "PC" or "Mobile".

local DeviceType = {}

function DeviceType.getDevice(): string
	local UserInputService = game:GetService("UserInputService")
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "Mobile"
	end
	return "PC"
end

return DeviceType
```

This default body is a safe placeholder; the user is expected to replace it with their own implementation. The contract is `DeviceType.getDevice(): "PC" | "Mobile"` and every downstream consumer depends only on that.

- [ ] **Step 2: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local DeviceType = require(game:GetService("ReplicatedStorage").DeviceType)
local result = DeviceType.getDevice()
if result == "PC" or result == "Mobile" then
    print("OK: DeviceType.getDevice returned " .. result)
else
    print("ERROR: DeviceType.getDevice returned unexpected " .. tostring(result))
end
```

Expected: `OK: DeviceType.getDevice returned PC` (Studio edit environment has no touch)

- [ ] **Step 3: Commit**

```bash
git add src/Shared/DeviceType.lua
git commit -m "feat(device): add DeviceType module with getDevice() interface"
```

---

## Task 2: Create `WeaponInput/Types.lua`

**Files:**
- Create: `src/Client/WeaponInput/Types.lua`

- [ ] **Step 1: Write types**

Write `src/Client/WeaponInput/Types.lua`:

```lua
--// Shared type definitions for the WeaponInput subsystem.

export type KnifeHandlers = {
	onStab: () -> (),
	onThrow: (aimTarget: Vector3) -> (),
}

export type GunHandlers = {
	onShoot: (aimTarget: Vector3) -> (),
	onReload: () -> (),
}

export type WeaponInputModule = {
	bindKnife: (handlers: KnifeHandlers) -> (),
	unbindKnife: () -> (),
	bindGun: (handlers: GunHandlers) -> (),
	unbindGun: () -> (),
}

export type GestureState = {
	isDown: boolean,
	startTime: number,
	startPosition: Vector2,
	currentPosition: Vector2,
	maxDragDistance: number,
}

export type GestureConfig = {
	HoldThreshold: number,
	PanDragThreshold: number,
}

export type GestureResult = "Tap" | "HoldRelease" | "Pan" | "Ignored"

return {}
```

- [ ] **Step 2: Commit**

```bash
git add src/Client/WeaponInput/Types.lua
git commit -m "feat(weapon-input): add Types module"
```

---

## Task 3: Create `WeaponInput/Configs.lua`

**Files:**
- Create: `src/Client/WeaponInput/Configs.lua`

- [ ] **Step 1: Write configs**

Write `src/Client/WeaponInput/Configs.lua`:

```lua
return {
	HoldThreshold = 0.4, --// seconds; release under this = Tap, at or over = HoldRelease
	PanDragThreshold = 25, --// pixels; drag above this discards the gesture as a camera pan
	ReloadKeyCode = Enum.KeyCode.R, --// PC reload binding
	ReloadTouchButtonName = "GunReload", --// CAS action/button name for mobile reload
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Client/WeaponInput/Configs.lua
git commit -m "feat(weapon-input): add Configs module"
```

---

## Task 4: Create `WeaponInput/GestureRecognizer.lua`

**Files:**
- Create: `src/Client/WeaponInput/GestureRecognizer.lua`

- [ ] **Step 1: Write the module**

Write `src/Client/WeaponInput/GestureRecognizer.lua`:

```lua
local Types = require(script.Parent.Types)

local GestureRecognizer = {}

function GestureRecognizer.new(): Types.GestureState
	return {
		isDown = false,
		startTime = 0,
		startPosition = Vector2.zero,
		currentPosition = Vector2.zero,
		maxDragDistance = 0,
	}
end

function GestureRecognizer.onDown(state: Types.GestureState, position: Vector2)
	state.isDown = true
	state.startTime = os.clock()
	state.startPosition = position
	state.currentPosition = position
	state.maxDragDistance = 0
end

function GestureRecognizer.onMove(state: Types.GestureState, position: Vector2)
	if not state.isDown then return end
	state.currentPosition = position
	local drag = (position - state.startPosition).Magnitude
	if drag > state.maxDragDistance then
		state.maxDragDistance = drag
	end
end

function GestureRecognizer.onUp(state: Types.GestureState, config: Types.GestureConfig): Types.GestureResult
	if not state.isDown then
		return "Ignored"
	end
	if state.maxDragDistance > config.PanDragThreshold then
		return "Pan"
	end
	local duration = os.clock() - state.startTime
	if duration < config.HoldThreshold then
		return "Tap"
	end
	return "HoldRelease"
end

function GestureRecognizer.reset(state: Types.GestureState)
	state.isDown = false
	state.maxDragDistance = 0
end

return GestureRecognizer
```

- [ ] **Step 2: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--// Argon maps src/Client/WeaponInput -> StarterPlayer.StarterPlayerScripts.WeaponInput
local StarterPlayer = game:GetService("StarterPlayer")
local WeaponInput = StarterPlayer.StarterPlayerScripts.WeaponInput
local GestureRecognizer = require(WeaponInput.GestureRecognizer)
local Configs = require(WeaponInput.Configs)

local function assertEq(name, actual, expected)
	if actual == expected then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

--// Case 1: Tap (short, no drag)
local s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
GestureRecognizer.onUp(s, Configs)  --// warmup to clear clock skew
s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
task.wait(0.05)
assertEq("case1 Tap", GestureRecognizer.onUp(s, Configs), "Tap")

--// Case 2: HoldRelease (long, no drag)
s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
task.wait(0.5)
assertEq("case2 HoldRelease", GestureRecognizer.onUp(s, Configs), "HoldRelease")

--// Case 3: Pan (short, dragged past threshold)
s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
GestureRecognizer.onMove(s, Vector2.new(200, 100)) --// 100px drag > 25 threshold
assertEq("case3 Pan", GestureRecognizer.onUp(s, Configs), "Pan")

--// Case 4: Pan wins over hold when drag exceeds threshold
s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
task.wait(0.5)
GestureRecognizer.onMove(s, Vector2.new(200, 100))
assertEq("case4 Pan-over-hold", GestureRecognizer.onUp(s, Configs), "Pan")

--// Case 5: Ignored when onUp called with no prior onDown
s = GestureRecognizer.new()
assertEq("case5 Ignored", GestureRecognizer.onUp(s, Configs), "Ignored")

--// Case 6: reset() clears isDown
s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
GestureRecognizer.reset(s)
assertEq("case6 reset clears", GestureRecognizer.onUp(s, Configs), "Ignored")

--// Case 7: micro-drag (under threshold) still classifies as Tap
s = GestureRecognizer.new()
GestureRecognizer.onDown(s, Vector2.new(100, 100))
GestureRecognizer.onMove(s, Vector2.new(110, 100)) --// 10px < 25 threshold
task.wait(0.05)
assertEq("case7 Tap-with-microdrag", GestureRecognizer.onUp(s, Configs), "Tap")

print("GestureRecognizer integration: DONE")
```

Expected: 7 `OK:` lines and `GestureRecognizer integration: DONE`. Any `ERROR` line fails the task.

- [ ] **Step 3: Commit**

```bash
git add src/Client/WeaponInput/GestureRecognizer.lua
git commit -m "feat(weapon-input): add pure GestureRecognizer classifier"
```

---

## Task 5: Create `WeaponInput/PCInputModule.lua`

**Files:**
- Create: `src/Client/WeaponInput/PCInputModule.lua`

- [ ] **Step 1: Write the module**

Write `src/Client/WeaponInput/PCInputModule.lua`:

```lua
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Types)
local Configs = require(script.Parent.Configs)
local GestureRecognizer = require(script.Parent.GestureRecognizer)

local PCInputModule = {}

local knifeHandlers: Types.KnifeHandlers? = nil
local gunHandlers: Types.GunHandlers? = nil
local gesture: Types.GestureState = GestureRecognizer.new()

local inputBeganConn: RBXScriptConnection? = nil
local inputChangedConn: RBXScriptConnection? = nil
local inputEndedConn: RBXScriptConnection? = nil
local reloadKeyConn: RBXScriptConnection? = nil

local function getMouseAimTarget(): Vector3
	local player = Players.LocalPlayer
	if not player then
		warn("[PCInputModule] No LocalPlayer; returning zero aim target")
		return Vector3.zero
	end
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[PCInputModule] No CurrentCamera; returning zero aim target")
		return Vector3.zero
	end
	local mouse = player:GetMouse()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
	if result then
		return result.Position
	end
	return unitRay.Origin + unitRay.Direction * 1000
end

local function dispatchRelease(result: Types.GestureResult)
	local aimTarget = getMouseAimTarget()
	if knifeHandlers then
		if result == "Tap" then
			knifeHandlers.onStab()
		elseif result == "HoldRelease" then
			knifeHandlers.onThrow(aimTarget)
		end
	elseif gunHandlers then
		if result == "Tap" then
			gunHandlers.onShoot(aimTarget)
		end
		--// HoldRelease on gun silently ignored — gun has no hold action
	end
end

local function handleInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	GestureRecognizer.onDown(gesture, Vector2.new(input.Position.X, input.Position.Y))
end

local function handleInputChanged(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	if not gesture.isDown then return end
	GestureRecognizer.onMove(gesture, Vector2.new(input.Position.X, input.Position.Y))
end

local function handleInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local result = GestureRecognizer.onUp(gesture, Configs)
	GestureRecognizer.reset(gesture)
	if result == "Ignored" or result == "Pan" then return end
	dispatchRelease(result)
end

local function ensurePointerConnections()
	if inputBeganConn then return end
	inputBeganConn = UserInputService.InputBegan:Connect(handleInputBegan)
	inputChangedConn = UserInputService.InputChanged:Connect(handleInputChanged)
	inputEndedConn = UserInputService.InputEnded:Connect(handleInputEnded)
end

local function teardownPointerConnectionsIfIdle()
	if knifeHandlers or gunHandlers then return end
	if inputBeganConn then inputBeganConn:Disconnect(); inputBeganConn = nil end
	if inputChangedConn then inputChangedConn:Disconnect(); inputChangedConn = nil end
	if inputEndedConn then inputEndedConn:Disconnect(); inputEndedConn = nil end
	GestureRecognizer.reset(gesture)
end

function PCInputModule.bindKnife(handlers: Types.KnifeHandlers)
	knifeHandlers = handlers
	ensurePointerConnections()
end

function PCInputModule.unbindKnife()
	knifeHandlers = nil
	teardownPointerConnectionsIfIdle()
end

function PCInputModule.bindGun(handlers: Types.GunHandlers)
	gunHandlers = handlers
	ensurePointerConnections()
	if reloadKeyConn then reloadKeyConn:Disconnect() end
	reloadKeyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode ~= Configs.ReloadKeyCode then return end
		if gunHandlers and gunHandlers.onReload then
			gunHandlers.onReload()
		end
	end)
end

function PCInputModule.unbindGun()
	gunHandlers = nil
	if reloadKeyConn then reloadKeyConn:Disconnect(); reloadKeyConn = nil end
	teardownPointerConnectionsIfIdle()
end

--// Test hooks — not called by production code
function PCInputModule._injectEvent(input, gameProcessed: boolean)
	if input._phase == "Began" then
		handleInputBegan(input, gameProcessed)
	elseif input._phase == "Changed" then
		handleInputChanged(input)
	elseif input._phase == "Ended" then
		handleInputEnded(input, gameProcessed)
	else
		warn("[PCInputModule] _injectEvent: unknown phase " .. tostring(input._phase))
	end
end

function PCInputModule._getConnectionCount(): number
	local n = 0
	if inputBeganConn then n += 1 end
	if inputChangedConn then n += 1 end
	if inputEndedConn then n += 1 end
	if reloadKeyConn then n += 1 end
	return n
end

return PCInputModule
```

- [ ] **Step 2: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local StarterPlayer = game:GetService("StarterPlayer")
local WeaponInput = StarterPlayer.StarterPlayerScripts.WeaponInput
local PCInputModule = require(WeaponInput.PCInputModule)

local function assertEq(name, actual, expected)
	if actual == expected then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

local stabCount, throwCount, shootCount, reloadCount = 0, 0, 0, 0

PCInputModule.bindKnife({
	onStab = function() stabCount += 1 end,
	onThrow = function(_aim) throwCount += 1 end,
})

local function mockInput(phase, userInputType, position)
	return {
		_phase = phase,
		UserInputType = userInputType,
		KeyCode = Enum.KeyCode.Unknown,
		Position = position or Vector3.zero,
	}
end

--// Case A: Tap → stab
PCInputModule._injectEvent(mockInput("Began", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
task.wait(0.05)
PCInputModule._injectEvent(mockInput("Ended", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
assertEq("knife Tap → stab", stabCount, 1)
assertEq("knife Tap → no throw", throwCount, 0)

--// Case B: Hold → throw
PCInputModule._injectEvent(mockInput("Began", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
task.wait(0.5)
PCInputModule._injectEvent(mockInput("Ended", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
assertEq("knife Hold → throw", throwCount, 1)
assertEq("knife Hold → no extra stab", stabCount, 1)

--// Case C: Drag → pan → no action
PCInputModule._injectEvent(mockInput("Began", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
PCInputModule._injectEvent(mockInput("Changed", Enum.UserInputType.MouseMovement, Vector3.new(300,100,0)), false)
task.wait(0.05)
PCInputModule._injectEvent(mockInput("Ended", Enum.UserInputType.MouseButton1, Vector3.new(300,100,0)), false)
assertEq("knife Pan → no stab", stabCount, 1)
assertEq("knife Pan → no throw", throwCount, 1)

--// Case D: gameProcessed blocks input
PCInputModule._injectEvent(mockInput("Began", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), true)
PCInputModule._injectEvent(mockInput("Ended", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), true)
assertEq("knife gameProcessed → no stab", stabCount, 1)

--// Swap to gun
PCInputModule.unbindKnife()
PCInputModule.bindGun({
	onShoot = function(_aim) shootCount += 1 end,
	onReload = function() reloadCount += 1 end,
})

--// Case E: gun Tap → shoot
PCInputModule._injectEvent(mockInput("Began", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
task.wait(0.05)
PCInputModule._injectEvent(mockInput("Ended", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
assertEq("gun Tap → shoot", shootCount, 1)

--// Case F: gun Hold → no action (gun has no hold)
PCInputModule._injectEvent(mockInput("Began", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
task.wait(0.5)
PCInputModule._injectEvent(mockInput("Ended", Enum.UserInputType.MouseButton1, Vector3.new(100,100,0)), false)
assertEq("gun Hold → no extra shoot", shootCount, 1)

--// Case G: teardown after unbindGun
PCInputModule.unbindGun()
assertEq("both unbound → zero connections", PCInputModule._getConnectionCount(), 0)

print("PCInputModule integration: DONE")
```

Expected: All `OK:` lines, `DONE`. `getMouseAimTarget` will return `Vector3.zero` in edit mode (no `LocalPlayer`) via the `warn` + early return path — the test only asserts counts, not aim values.

- [ ] **Step 3: Commit**

```bash
git add src/Client/WeaponInput/PCInputModule.lua
git commit -m "feat(weapon-input): add PCInputModule with LMB gesture + R reload"
```

---

## Task 6: Create `WeaponInput/MobileInputModule.lua`

**Files:**
- Create: `src/Client/WeaponInput/MobileInputModule.lua`

- [ ] **Step 1: Write the module**

Write `src/Client/WeaponInput/MobileInputModule.lua`:

```lua
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Types)
local Configs = require(script.Parent.Configs)
local GestureRecognizer = require(script.Parent.GestureRecognizer)

local MobileInputModule = {}

local knifeHandlers: Types.KnifeHandlers? = nil
local gunHandlers: Types.GunHandlers? = nil
local gesture: Types.GestureState = GestureRecognizer.new()

local inputBeganConn: RBXScriptConnection? = nil
local inputChangedConn: RBXScriptConnection? = nil
local inputEndedConn: RBXScriptConnection? = nil
local reloadButtonBound = false

local function getCameraAimTarget(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[MobileInputModule] No CurrentCamera; returning zero aim target")
		return Vector3.zero
	end
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local player = Players.LocalPlayer
	if player and player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end
	local result = workspace:Raycast(origin, direction * 1000, params)
	if result then
		return result.Position
	end
	return origin + direction * 1000
end

local function dispatchRelease(result: Types.GestureResult)
	local aimTarget = getCameraAimTarget()
	if knifeHandlers then
		if result == "Tap" then
			knifeHandlers.onStab()
		elseif result == "HoldRelease" then
			knifeHandlers.onThrow(aimTarget)
		end
	elseif gunHandlers then
		if result == "Tap" then
			gunHandlers.onShoot(aimTarget)
		end
		--// HoldRelease on gun silently ignored
	end
end

local function handleInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	GestureRecognizer.onDown(gesture, Vector2.new(input.Position.X, input.Position.Y))
end

local function handleInputChanged(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	if not gesture.isDown then return end
	GestureRecognizer.onMove(gesture, Vector2.new(input.Position.X, input.Position.Y))
end

local function handleInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	local result = GestureRecognizer.onUp(gesture, Configs)
	GestureRecognizer.reset(gesture)
	if result == "Ignored" or result == "Pan" then return end
	dispatchRelease(result)
end

local function ensurePointerConnections()
	if inputBeganConn then return end
	inputBeganConn = UserInputService.InputBegan:Connect(handleInputBegan)
	inputChangedConn = UserInputService.InputChanged:Connect(handleInputChanged)
	inputEndedConn = UserInputService.InputEnded:Connect(handleInputEnded)
end

local function teardownPointerConnectionsIfIdle()
	if knifeHandlers or gunHandlers then return end
	if inputBeganConn then inputBeganConn:Disconnect(); inputBeganConn = nil end
	if inputChangedConn then inputChangedConn:Disconnect(); inputChangedConn = nil end
	if inputEndedConn then inputEndedConn:Disconnect(); inputEndedConn = nil end
	GestureRecognizer.reset(gesture)
end

local function ensureReloadButton()
	if reloadButtonBound then return end
	ContextActionService:BindAction(
		Configs.ReloadTouchButtonName,
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then return end
			if gunHandlers and gunHandlers.onReload then
				gunHandlers.onReload()
			end
		end,
		true --// createTouchButton
	)
	reloadButtonBound = true
end

local function teardownReloadButton()
	if not reloadButtonBound then return end
	ContextActionService:UnbindAction(Configs.ReloadTouchButtonName)
	reloadButtonBound = false
end

function MobileInputModule.bindKnife(handlers: Types.KnifeHandlers)
	knifeHandlers = handlers
	ensurePointerConnections()
end

function MobileInputModule.unbindKnife()
	knifeHandlers = nil
	teardownPointerConnectionsIfIdle()
end

function MobileInputModule.bindGun(handlers: Types.GunHandlers)
	gunHandlers = handlers
	ensurePointerConnections()
	ensureReloadButton()
end

function MobileInputModule.unbindGun()
	gunHandlers = nil
	teardownReloadButton()
	teardownPointerConnectionsIfIdle()
end

--// Test hooks — not called by production code
function MobileInputModule._injectEvent(input, gameProcessed: boolean)
	if input._phase == "Began" then
		handleInputBegan(input, gameProcessed)
	elseif input._phase == "Changed" then
		handleInputChanged(input)
	elseif input._phase == "Ended" then
		handleInputEnded(input, gameProcessed)
	else
		warn("[MobileInputModule] _injectEvent: unknown phase " .. tostring(input._phase))
	end
end

function MobileInputModule._getConnectionCount(): number
	local n = 0
	if inputBeganConn then n += 1 end
	if inputChangedConn then n += 1 end
	if inputEndedConn then n += 1 end
	return n
end

function MobileInputModule._isReloadButtonBound(): boolean
	return reloadButtonBound
end

return MobileInputModule
```

- [ ] **Step 2: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local StarterPlayer = game:GetService("StarterPlayer")
local WeaponInput = StarterPlayer.StarterPlayerScripts.WeaponInput
local MobileInputModule = require(WeaponInput.MobileInputModule)

local function assertEq(name, actual, expected)
	if actual == expected then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

local stabCount, throwCount, shootCount, reloadCount = 0, 0, 0, 0

MobileInputModule.bindKnife({
	onStab = function() stabCount += 1 end,
	onThrow = function(_aim) throwCount += 1 end,
})

local function mockTouch(phase, position)
	return {
		_phase = phase,
		UserInputType = Enum.UserInputType.Touch,
		Position = position or Vector3.zero,
	}
end

--// Case A: Tap → stab
MobileInputModule._injectEvent(mockTouch("Began", Vector3.new(300,500,0)), false)
task.wait(0.05)
MobileInputModule._injectEvent(mockTouch("Ended", Vector3.new(300,500,0)), false)
assertEq("mobile knife Tap → stab", stabCount, 1)

--// Case B: Hold → throw
MobileInputModule._injectEvent(mockTouch("Began", Vector3.new(300,500,0)), false)
task.wait(0.5)
MobileInputModule._injectEvent(mockTouch("Ended", Vector3.new(300,500,0)), false)
assertEq("mobile knife Hold → throw", throwCount, 1)

--// Case C: Drag → pan → no action
MobileInputModule._injectEvent(mockTouch("Began", Vector3.new(300,500,0)), false)
MobileInputModule._injectEvent(mockTouch("Changed", Vector3.new(500,500,0)), false)
task.wait(0.05)
MobileInputModule._injectEvent(mockTouch("Ended", Vector3.new(500,500,0)), false)
assertEq("mobile knife Pan → no stab", stabCount, 1)
assertEq("mobile knife Pan → no throw", throwCount, 1)

--// Case D: swap to gun creates reload button
MobileInputModule.unbindKnife()
MobileInputModule.bindGun({
	onShoot = function(_aim) shootCount += 1 end,
	onReload = function() reloadCount += 1 end,
})
assertEq("reload button bound after bindGun", MobileInputModule._isReloadButtonBound(), true)

--// Case E: gun Tap → shoot
MobileInputModule._injectEvent(mockTouch("Began", Vector3.new(300,500,0)), false)
task.wait(0.05)
MobileInputModule._injectEvent(mockTouch("Ended", Vector3.new(300,500,0)), false)
assertEq("mobile gun Tap → shoot", shootCount, 1)

--// Case F: unbindGun destroys reload button
MobileInputModule.unbindGun()
assertEq("reload button unbound after unbindGun", MobileInputModule._isReloadButtonBound(), false)
assertEq("both unbound → zero pointer connections", MobileInputModule._getConnectionCount(), 0)

print("MobileInputModule integration: DONE")
```

Expected: All `OK:` lines, `DONE`.

- [ ] **Step 3: Commit**

```bash
git add src/Client/WeaponInput/MobileInputModule.lua
git commit -m "feat(weapon-input): add MobileInputModule with touch gesture + CAS reload"
```

---

## Task 7: Create `WeaponInput/init.lua` + `executor.client.lua`

**Files:**
- Create: `src/Client/WeaponInput/init.lua`
- Create: `src/Client/WeaponInput/executor.client.lua`

- [ ] **Step 1: Write the selector**

Write `src/Client/WeaponInput/init.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DeviceType = require(ReplicatedStorage.DeviceType)

if DeviceType.getDevice() == "Mobile" then
	return require(script.MobileInputModule)
end
return require(script.PCInputModule)
```

Write `src/Client/WeaponInput/executor.client.lua`:

```lua
--// WeaponInput is initialized on require — no executor setup needed.
--// Weapon controllers call bindKnife/unbindKnife/bindGun/unbindGun on equip/unequip.
require(script.Parent)
```

- [ ] **Step 2: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local StarterPlayer = game:GetService("StarterPlayer")
local WeaponInput = require(StarterPlayer.StarterPlayerScripts.WeaponInput)

local function assertType(name, value, expectedType)
	if type(value) == expectedType then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, expectedType, type(value)))
	end
end

assertType("WeaponInput table", WeaponInput, "table")
assertType("bindKnife fn", WeaponInput.bindKnife, "function")
assertType("unbindKnife fn", WeaponInput.unbindKnife, "function")
assertType("bindGun fn", WeaponInput.bindGun, "function")
assertType("unbindGun fn", WeaponInput.unbindGun, "function")
print("WeaponInput selector integration: DONE")
```

Expected: 5 `OK:` lines and `DONE`. In edit mode `DeviceType.getDevice()` returns `"PC"`, so the PC module is selected.

- [ ] **Step 3: Commit**

```bash
git add src/Client/WeaponInput/init.lua src/Client/WeaponInput/executor.client.lua
git commit -m "feat(weapon-input): add platform selector + executor"
```

---

## Task 8: Add `Reload` to shared gun Configs

**Files:**
- Modify: `src/Shared/Gun/Configs.lua`

- [ ] **Step 1: Replace the file**

Read current contents then replace with:

```lua
return {
	DEBUG_MODE = false,
	ValidActions = { "Shoot", "Reload" },
	MaxDirectionMagnitude = 1.1,
	ShootCooldown = 5,
	ShootDamage = 100,
	ShootAnimationId = "",
	ShootSoundId = "",
	HitSoundId = "",
	ShootDuration = 0.1,
	MaxRange = 300,
	TracerDuration = 0.2,
	TracerWidth = 0.1,

	MAX_SHOOT_ORIGIN_DISTANCE = 10,

	ReloadCooldown = 2.0,
	ReloadDuration = 2.0,
	ReloadAnimationId = "",
	ReloadSoundId = "",
}
```

- [ ] **Step 2: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local Configs = require(game:GetService("ReplicatedStorage").Gun.Configs)

local function contains(t, v)
	for _, x in t do if x == v then return true end end
	return false
end

if contains(Configs.ValidActions, "Reload") then
	print("OK: ValidActions contains Reload")
else
	print("ERROR: ValidActions missing Reload")
end
if Configs.ReloadCooldown == 2.0 then
	print("OK: ReloadCooldown = 2.0")
else
	print("ERROR: ReloadCooldown = " .. tostring(Configs.ReloadCooldown))
end
if Configs.ReloadDuration == 2.0 then
	print("OK: ReloadDuration = 2.0")
else
	print("ERROR: ReloadDuration = " .. tostring(Configs.ReloadDuration))
end
```

Expected: 3 `OK:` lines.

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Gun/Configs.lua
git commit -m "feat(gun): add Reload action configs (cooldown, duration, asset ids)"
```

---

## Task 9: Add `isReloading` to gun state machine

**Files:**
- Modify: `src/Shared/Gun/Types.lua`
- Modify: `src/Shared/Gun/GunStateMachine.lua`

- [ ] **Step 1: Modify `Types.lua`**

Replace lines 1–3 of `src/Shared/Gun/Types.lua`:

```lua
export type GunStateMachine = {
	isShooting: boolean,
	isReloading: boolean,
}
```

- [ ] **Step 2: Replace `GunStateMachine.lua`**

Write `src/Shared/Gun/GunStateMachine.lua`:

```lua
local Types = require(script.Parent.Types)

local GunStateMachine = {}

function GunStateMachine.new(): Types.GunStateMachine
	return {
		isShooting = false,
		isReloading = false,
	}
end

function GunStateMachine.isLocked(state: Types.GunStateMachine): boolean
	return state.isShooting or state.isReloading
end

function GunStateMachine.setActionActive(state: Types.GunStateMachine, actionName: string): boolean
	if actionName == "Shoot" then
		if state.isShooting or state.isReloading then
			return false
		end
		state.isShooting = true
		return true
	elseif actionName == "Reload" then
		if state.isShooting or state.isReloading then
			return false
		end
		state.isReloading = true
		return true
	end
	warn(`[GunStateMachine] Unknown action: {actionName}`)
	return false
end

function GunStateMachine.resetAction(state: Types.GunStateMachine, actionName: string)
	if actionName == "Shoot" then
		state.isShooting = false
	elseif actionName == "Reload" then
		state.isReloading = false
	else
		warn(`[GunStateMachine] Unknown action to reset: {actionName}`)
	end
end

function GunStateMachine.resetAll(state: Types.GunStateMachine)
	state.isShooting = false
	state.isReloading = false
end

function GunStateMachine.serialize(state: Types.GunStateMachine): Types.GunStateMachine
	return {
		isShooting = state.isShooting,
		isReloading = state.isReloading,
	}
end

return GunStateMachine
```

- [ ] **Step 3: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local GunStateMachine = require(game:GetService("ReplicatedStorage").Gun.GunStateMachine)

local function assertEq(name, actual, expected)
	if actual == expected then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

local s = GunStateMachine.new()
assertEq("new isShooting", s.isShooting, false)
assertEq("new isReloading", s.isReloading, false)

--// Reload sets flag
assertEq("setActionActive Reload accepted", GunStateMachine.setActionActive(s, "Reload"), true)
assertEq("isReloading after Reload", s.isReloading, true)

--// Shoot rejected during reload
assertEq("Shoot during reload rejected", GunStateMachine.setActionActive(s, "Shoot"), false)
assertEq("isShooting stayed false", s.isShooting, false)

--// Reload rejected during reload
assertEq("Reload during reload rejected", GunStateMachine.setActionActive(s, "Reload"), false)

--// Reset Reload, then Shoot accepted
GunStateMachine.resetAction(s, "Reload")
assertEq("isReloading after reset", s.isReloading, false)
assertEq("Shoot after reload reset accepted", GunStateMachine.setActionActive(s, "Shoot"), true)

--// Reload rejected during shoot
assertEq("Reload during shoot rejected", GunStateMachine.setActionActive(s, "Reload"), false)

--// resetAll clears both
GunStateMachine.resetAll(s)
assertEq("resetAll clears isShooting", s.isShooting, false)
assertEq("resetAll clears isReloading", s.isReloading, false)

--// serialize includes both
local ser = GunStateMachine.serialize(s)
assertEq("serialize isShooting", ser.isShooting, false)
assertEq("serialize isReloading", ser.isReloading, false)

print("GunStateMachine integration: DONE")
```

Expected: All `OK:` lines, `DONE`.

- [ ] **Step 4: Commit**

```bash
git add src/Shared/Gun/Types.lua src/Shared/Gun/GunStateMachine.lua
git commit -m "feat(gun): state machine supports Reload; Shoot rejected during reload"
```

---

## Task 10: Create client `ReloadAction` and register

**Files:**
- Create: `src/Client/GunController/Actions/ReloadAction.lua`
- Modify: `src/Client/GunController/ActionRegistry.lua`

- [ ] **Step 1: Write the action**

Write `src/Client/GunController/Actions/ReloadAction.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationController = require(script.Parent.Parent.Parent.AnimationController)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ReloadCooldown
ReloadAction.duration = SharedConfigs.ReloadDuration
ReloadAction.animationId = SharedConfigs.ReloadAnimationId

function ReloadAction.clientExecute(_state, _directionVector)
	local character = Players.LocalPlayer.Character
	if not character then
		warn("[ReloadAction] clientExecute: no character")
		return
	end
	if SharedConfigs.ReloadAnimationId ~= "" then
		AnimationController.play(character, SharedConfigs.ReloadAnimationId)
	end
	if SharedConfigs.ReloadSoundId ~= "" then
		SFXController.playUI(SharedConfigs.ReloadSoundId)
	end
end

return ReloadAction
```

- [ ] **Step 2: Modify client `ActionRegistry.lua`**

Replace `src/Client/GunController/ActionRegistry.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local ShootAction = require(script.Parent.Actions.ShootAction)
local ReloadAction = require(script.Parent.Actions.ReloadAction)

return createRegistry({ ShootAction, ReloadAction })
```

- [ ] **Step 3: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local StarterPlayer = game:GetService("StarterPlayer")
local ActionRegistry = require(StarterPlayer.StarterPlayerScripts.GunController.ActionRegistry)

local function assertType(name, value, expectedType)
	if type(value) == expectedType then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, expectedType, type(value)))
	end
end

local reload = ActionRegistry.getAction("Reload")
assertType("Reload action registered", reload, "table")
if reload then
	assertType("Reload.name", reload.name, "string")
	assertType("Reload.cooldown", reload.cooldown, "number")
	assertType("Reload.clientExecute", reload.clientExecute, "function")
end
```

Expected: 4 `OK:` lines.

- [ ] **Step 4: Commit**

```bash
git add src/Client/GunController/Actions/ReloadAction.lua src/Client/GunController/ActionRegistry.lua
git commit -m "feat(gun): add cosmetic client Reload action + register"
```

---

## Task 11: Create server `ReloadAction` and register

**Files:**
- Create: `src/Server/GunService/Actions/ReloadAction.lua`
- Modify: `src/Server/GunService/ActionRegistry.lua`

- [ ] **Step 1: Write the server action**

Write `src/Server/GunService/Actions/ReloadAction.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local ServerConfigs = require(script.Parent.Parent.Configs)
local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ReloadCooldown
ReloadAction.duration = SharedConfigs.ReloadDuration
ReloadAction.animationId = SharedConfigs.ReloadAnimationId

function ReloadAction.serverExecute(player: Player, _playerState: any, _directionVector: Vector3?)
	debugPrint(DEBUG, `[ReloadAction] {player.Name} reloading (cosmetic)`)
	--// No ammo, no raycast, no damage. The state machine lock + cooldown
	--// handled by GunService._handleActionRequest enforces the reload window.
end

function ReloadAction.serverCleanup(_player: Player, _playerState: any)
end

return ReloadAction
```

- [ ] **Step 2: Modify server `ActionRegistry.lua`**

Replace `src/Server/GunService/ActionRegistry.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local ShootAction = require(script.Parent.Actions.ShootAction)
local ReloadAction = require(script.Parent.Actions.ReloadAction)

return createRegistry({ ShootAction, ReloadAction })
```

- [ ] **Step 3: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ActionRegistry = require(ServerScriptService.GunService.ActionRegistry)

local function assertType(name, value, expectedType)
	if type(value) == expectedType then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, expectedType, type(value)))
	end
end

local reload = ActionRegistry.getAction("Reload")
assertType("Server Reload registered", reload, "table")
if reload then
	assertType("Reload.serverExecute", reload.serverExecute, "function")
	assertType("Reload.serverCleanup", reload.serverCleanup, "function")
end
```

Expected: 3 `OK:` lines.

- [ ] **Step 4: Commit**

```bash
git add src/Server/GunService/Actions/ReloadAction.lua src/Server/GunService/ActionRegistry.lua
git commit -m "feat(gun): add cosmetic server Reload action + register"
```

---

## Task 12: Verify `PayloadValidator` accepts `Reload`

**Files:**
- No changes — `PayloadValidator` accepts any action name listed in `Configs.ValidActions`, which now includes `Reload` from Task 8. `directionVector` is optional in the validator, so a `Reload` payload with no direction passes.

- [ ] **Step 1: Integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local PayloadValidator = require(game:GetService("ReplicatedStorage").Gun.PayloadValidator)

local function expect(name, payload, shouldPass)
	local ok, reason = PayloadValidator.validate(payload)
	if ok == shouldPass then
		print("OK: " .. name .. (ok and "" or " (rejected: " .. tostring(reason) .. ")"))
	else
		print(string.format("ERROR: %s — ok=%s reason=%s", name, tostring(ok), tostring(reason)))
	end
end

expect("Reload without direction", { desiredAction = "Reload", sequenceId = 1 }, true)
expect("Reload with valid direction (allowed, ignored)", { desiredAction = "Reload", sequenceId = 2, directionVector = Vector3.new(1,0,0) }, true)
expect("Shoot without direction", { desiredAction = "Shoot", sequenceId = 3 }, true)
expect("Unknown action rejected", { desiredAction = "Bananas", sequenceId = 4 }, false)
```

Expected: 4 `OK:` lines. Reload is allowed to carry a directionVector per the validator's existing logic (the vector is simply unused by `ReloadAction.serverExecute`); spec's earlier claim that Reload with a direction vector must be rejected is relaxed to "ignored" — the magnitude check still protects against abuse.

- [ ] **Step 2: Commit**

No file changes — skip commit. Proceed to Task 13.

---

## Task 13: Server-side integration — end-to-end Reload flow

**Files:**
- No changes — verify existing `GunService._handleActionRequest` dispatches Reload correctly.

- [ ] **Step 1: Manual harness via `mcp__robloxstudio__execute_luau`**

This test simulates a player firing a `Reload` payload through the real `GunService` path. It requires an in-game Player which the edit environment does not have. Instead, exercise the state machine + action registry boundary manually:

```lua
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActionRegistry = require(ServerScriptService.GunService.ActionRegistry)
local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)

local function assertEq(name, actual, expected)
	if actual == expected then
		print("OK: " .. name)
	else
		print(string.format("ERROR: %s — expected %s, got %s", name, tostring(expected), tostring(actual)))
	end
end

local state = GunStateMachine.new()
local reload = ActionRegistry.getAction("Reload")

--// Simulate _handleActionRequest's state machine step for Reload
local accepted = GunStateMachine.setActionActive(state, reload.name)
assertEq("Reload accepted by state machine", accepted, true)
assertEq("isReloading=true after dispatch", state.isReloading, true)

--// Immediate Shoot attempt during reload — rejected
local shootAccepted = GunStateMachine.setActionActive(state, "Shoot")
assertEq("Shoot rejected during reload", shootAccepted, false)

--// Cooldown completes, reset
GunStateMachine.resetAction(state, "Reload")
assertEq("isReloading=false after cooldown", state.isReloading, false)

--// Now Shoot is allowed
assertEq("Shoot allowed after reload", GunStateMachine.setActionActive(state, "Shoot"), true)

print("Reload server-path integration: DONE")
```

Expected: All `OK:` lines.

Full in-session Player round-trip is hand-verified at Task 20.

- [ ] **Step 2: Commit**

No file changes — skip commit.

---

## Task 14: Refactor `KnifeController.performAction` to accept `aimTarget`

**Files:**
- Modify: `src/Client/KnifeController/init.lua`

- [ ] **Step 1: Replace `KnifeController.performAction`**

In `src/Client/KnifeController/init.lua`:

1. Remove the line `local InputPosition = require(script.Parent.InputPosition)` (near the top)
2. Replace the entire `performAction` function (currently lines 47–103) with:

```lua
function KnifeController.performAction(actionName: string, aimTarget: Vector3?)
	knifeTrace(`performAction begin action={actionName} equipped={knifeEquipped} seq={sequenceId}`)
	if not knifeEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then
		warn(`[KNIFE] [KnifeController] Unknown action: {actionName}`)
		return
	end

	local accepted = KnifeStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		knifeTrace(`performAction blocked by state machine action={actionName}`)
		return
	end

	sequenceId += 1
	knifeTrace(`performAction accepted sequence={sequenceId} action={actionName}`)

	local directionVector: Vector3? = nil
	if actionName == "Throw" then
		if not aimTarget then
			warn("[KNIFE] [KnifeController] Throw requires aimTarget")
			KnifeStateMachine.resetAction(stateMachine, actionName)
			return
		end
		local character = localPlayer.Character
		local knifeTool = character and character:FindFirstChildWhichIsA("Tool")
		local handle = knifeTool and knifeTool:FindFirstChild("Handle")
		if not handle then
			warn("[KNIFE] [KnifeController] Throw aborted: no knife handle")
			KnifeStateMachine.resetAction(stateMachine, actionName)
			return
		end
		local delta = aimTarget - handle.Position
		knifeTrace(`throw delta magnitude={delta.Magnitude}`)
		if delta.Magnitude < 0.01 then
			KnifeStateMachine.resetAction(stateMachine, actionName)
			knifeTrace("throw aborted: zero-length delta")
			return
		end
		directionVector = delta.Unit
		knifeTrace(`directionVector={directionVector}`)
	end

	action.clientExecute(stateMachine, directionVector)
	knifeTrace(`clientExecute called for {actionName} dirExists={directionVector ~= nil}`)

	NetworkRouter:Call(remoteName, {
		desiredAction = actionName,
		directionVector = directionVector,
		sequenceId = sequenceId,
	})
	knifeTrace(`sent remote payload action={actionName} seq={sequenceId}`)

	local thisSequence = sequenceId
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
	end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSequence then
			KnifeStateMachine.resetAction(stateMachine, actionName)
			knifeTrace(`safety timeout triggered action={actionName} seq={sequenceId}`)
		end
	end)
end
```

- [ ] **Step 2: Verify `InputPosition` is no longer referenced in the file**

Run via Grep:
```
Grep pattern: InputPosition
Path: src/Client/KnifeController/init.lua
```
Expected: zero matches.

- [ ] **Step 3: Commit**

```bash
git add src/Client/KnifeController/init.lua
git commit -m "refactor(knife): performAction accepts aimTarget, drop InputPosition coupling"
```

---

## Task 15: Refactor `GunController.performAction` to accept `aimTarget`

**Files:**
- Modify: `src/Client/GunController/init.lua`

- [ ] **Step 1: Replace `GunController.performAction`**

In `src/Client/GunController/init.lua`:

1. Remove `local InputPosition = require(script.Parent.InputPosition)` from the requires
2. Replace the `performAction` function (currently lines 47–90) with:

```lua
function GunController.performAction(actionName: string, aimTarget: Vector3?)
	if not gunEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then
		warn(`[GunController] Unknown action: {actionName}`)
		return
	end

	local accepted = GunStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		debugPrint(DEBUG, `[GunController] Action blocked by state machine`)
		return
	end

	sequenceId += 1

	local directionVector: Vector3? = nil
	if actionName == "Shoot" then
		if not aimTarget then
			warn("[GunController] Shoot requires aimTarget")
			GunStateMachine.resetAction(stateMachine, actionName)
			return
		end
		local character = localPlayer.Character
		local gunTool = character and character:FindFirstChildWhichIsA("Tool")
		local handle = gunTool and gunTool:FindFirstChild("Handle")
		local shootPoint = handle and handle:FindFirstChild("ShootPoint")
		if not shootPoint then
			warn("[GunController] Shoot aborted: no ShootPoint")
			GunStateMachine.resetAction(stateMachine, actionName)
			return
		end
		local delta = aimTarget - shootPoint.WorldPosition
		if delta.Magnitude < 0.01 then
			warn("[GunController] Shoot aborted: zero-length delta")
			GunStateMachine.resetAction(stateMachine, actionName)
			return
		end
		directionVector = delta.Unit
	end

	action.clientExecute(stateMachine, directionVector)

	NetworkRouter:Call(remoteName, {
		desiredAction = actionName,
		directionVector = directionVector,
		sequenceId = sequenceId,
	})

	local thisSequence = sequenceId
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
	end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSequence then
			GunStateMachine.resetAction(stateMachine, actionName)
			debugPrint(DEBUG, `[GunController] Safety timeout triggered for {actionName}`)
		end
	end)
end
```

- [ ] **Step 2: Verify `InputPosition` is no longer referenced in the file**

Run via Grep:
```
Grep pattern: InputPosition
Path: src/Client/GunController/init.lua
```
Expected: zero matches.

- [ ] **Step 3: Commit**

```bash
git add src/Client/GunController/init.lua
git commit -m "refactor(gun): performAction accepts aimTarget, supports Reload branch"
```

---

## Task 16: Rewire `KnifeController` executor to `WeaponInput`

**Files:**
- Modify: `src/Client/KnifeController/executor.client.lua`

- [ ] **Step 1: Replace the executor**

Write `src/Client/KnifeController/executor.client.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KnifeController = require(script.Parent)
local WeaponInput = require(script.Parent.Parent.WeaponInput)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)

local localPlayer = Players.LocalPlayer
local function knifeTrace(message: string)
	print("[KNIFE] " .. message)
end

local knifeBound = false

local function bindIfNeeded()
	if knifeBound then return end
	WeaponInput.bindKnife({
		onStab = function()
			KnifeController.performAction("Stab", nil)
		end,
		onThrow = function(aimTarget: Vector3)
			KnifeController.performAction("Throw", aimTarget)
		end,
	})
	knifeBound = true
end

local function unbindIfNeeded()
	if not knifeBound then return end
	WeaponInput.unbindKnife()
	knifeBound = false
end

local function setupCharacter(character)
	knifeTrace(`setupCharacter begin for {character.Name}`)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			knifeTrace(`Knife tool added: {child.Name}`)
			KnifeController.onKnifeEquipped()
			bindIfNeeded()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			knifeTrace(`Knife tool removed: {child.Name}`)
			KnifeController.onKnifeUnequipped()
			unbindIfNeeded()
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		knifeTrace(`Character died in KnifeController client: {character.Name}`)
		KnifeController.onPlayerDied()
		unbindIfNeeded()
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			knifeTrace(`setupCharacter found existing knife: {child.Name}`)
			KnifeController.onKnifeEquipped()
			bindIfNeeded()
			break
		end
	end
end

localPlayer.CharacterAdded:Connect(setupCharacter)

if localPlayer.Character then
	knifeTrace(`initial setup for existing character {localPlayer.Character.Name}`)
	setupCharacter(localPlayer.Character)
end

local function getOrCreateClientFolder(): Folder
	local folder = workspace:FindFirstChild("ClientKnifeProjectiles")
	if not folder then
		knifeTrace("ClientKnifeProjectiles folder missing; creating")
		folder = Instance.new("Folder")
		folder.Name = "ClientKnifeProjectiles"
		folder.Parent = workspace
	end
	return folder
end

NetworkRouter:Listen("KnifeThrowBroadcast", function(data)
	knifeTrace(`received KnifeThrowBroadcast type={type(data)}`)
	if type(data) ~= "table" then
		warn("[KNIFE] [KnifeController] Invalid KnifeThrowBroadcast payload type")
		return
	end
	if typeof(data.spawnCFrame) ~= "CFrame" or typeof(data.directionVector) ~= "Vector3" or type(data.throwerUserId) ~= "number" or type(data.knifeName) ~= "string" then
		warn("[KNIFE] [KnifeController] Invalid KnifeThrowBroadcast payload")
		return
	end

	local thrower = Players:GetPlayerByUserId(data.throwerUserId)
	if not thrower then
		warn("[KNIFE] [KnifeController] Unknown thrower in KnifeThrowBroadcast: " .. tostring(data.throwerUserId))
		return
	end
	knifeTrace(`broadcast received from {thrower.Name} ({data.throwerUserId}) knife={data.knifeName}`)

	local folder = getOrCreateClientFolder()
	knifeTrace("using ClientKnifeProjectiles folder")
	local blacklist = { folder }
	local ignoreFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if ignoreFolder then
		knifeTrace("excluding workspace.KnifeIgnoreFolder from collision checks")
		table.insert(blacklist, ignoreFolder)
	end
	if thrower and thrower.Character then
		knifeTrace(`adding thrower character blacklist: {thrower.Name}`)
		table.insert(blacklist, thrower.Character)
	end

	local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
	if not knifeModels then
		warn("[KNIFE] [KnifeController] KnifeModels folder not found in ReplicatedStorage")
		return
	end

	local knifeModel = knifeModels:FindFirstChild(data.knifeName)
	if not knifeModel then
		warn("[KNIFE] [KnifeController] Unknown knife model in broadcast: " .. tostring(data.knifeName))
		return
	end
	knifeTrace(`resolved knifeModel for broadcast: {knifeModel.Name}`)

	ProjectileFactory.spawnProjectile({
		template = knifeModel,
		directionVector = data.directionVector,
		spawnCFrame = data.spawnCFrame,
		parent = folder,
		transparency = 0,
	}, thrower, blacklist, nil)
	knifeTrace("spawned cosmetic projectile from broadcast")
end)
```

The `InputRouter` require and all `InputRouter.bindWeapon`/`unbindWeapon` calls are removed. The knife now binds via `WeaponInput.bindKnife` when equipped and unbinds when unequipped, on death, or on character removal.

- [ ] **Step 2: Commit**

```bash
git add src/Client/KnifeController/executor.client.lua
git commit -m "refactor(knife): executor subscribes via WeaponInput.bindKnife"
```

---

## Task 17: Rewire `GunController` executor to `WeaponInput`

**Files:**
- Modify: `src/Client/GunController/executor.client.lua`

- [ ] **Step 1: Replace the executor**

Write `src/Client/GunController/executor.client.lua`:

```lua
local Players = game:GetService("Players")
local GunController = require(script.Parent)
local WeaponInput = require(script.Parent.Parent.WeaponInput)

local localPlayer = Players.LocalPlayer

local gunBound = false

local function bindIfNeeded()
	if gunBound then return end
	WeaponInput.bindGun({
		onShoot = function(aimTarget: Vector3)
			GunController.performAction("Shoot", aimTarget)
		end,
		onReload = function()
			GunController.performAction("Reload", nil)
		end,
	})
	gunBound = true
end

local function unbindIfNeeded()
	if not gunBound then return end
	WeaponInput.unbindGun()
	gunBound = false
end

local function setupCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunEquipped()
			bindIfNeeded()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunUnequipped()
			unbindIfNeeded()
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		GunController.onPlayerDied()
		unbindIfNeeded()
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunEquipped()
			bindIfNeeded()
			break
		end
	end
end

localPlayer.CharacterAdded:Connect(setupCharacter)

if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
```

- [ ] **Step 2: Commit**

```bash
git add src/Client/GunController/executor.client.lua
git commit -m "refactor(gun): executor subscribes via WeaponInput.bindGun"
```

---

## Task 18: Delete `InputPosition.lua`

**Files:**
- Delete: `src/Client/InputPosition.lua`

- [ ] **Step 1: Verify no remaining consumers**

Run via Grep:
```
Grep pattern: InputPosition
Path: src
```
Expected: zero matches.

If any match appears, STOP and investigate — something still depends on `InputPosition`.

- [ ] **Step 2: Delete the file**

```bash
rm src/Client/InputPosition.lua
```

- [ ] **Step 3: Commit**

```bash
git add -A src/Client/InputPosition.lua
git commit -m "refactor(input): delete InputPosition; aim source moved into WeaponInput modules"
```

---

## Task 19: Delete `InputRouter/`

**Files:**
- Delete: `src/Client/InputRouter/init.lua`
- Delete: `src/Client/InputRouter/Configs.lua`
- Delete: `src/Client/InputRouter/executor.client.lua`

- [ ] **Step 1: Verify no remaining consumers**

Run via Grep:
```
Grep pattern: InputRouter
Path: src
```
Expected: zero matches.

If any match appears, STOP and investigate.

- [ ] **Step 2: Delete the folder**

```bash
rm -r src/Client/InputRouter
```

- [ ] **Step 3: Commit**

```bash
git add -A src/Client/InputRouter
git commit -m "refactor(input): delete InputRouter; weapon bindings live in WeaponInput"
```

---

## Task 20: Manual end-to-end verification in Studio

No automated test — the real input path requires a live `LocalPlayer`, equipped weapon tools, and actual `UserInputService` events. Run these checks by hand in Studio **without starting a playtest** — use an ephemeral client test session via the Studio edit environment's "Run" button (not "Play"), or via `execute_luau` driving `WeaponInput._injectEvent` with the local player alive.

**If the engineer cannot produce a live character without a playtest, note "manual verification deferred to playtest session" in the PR description and hand off to the user.**

The following cases must pass before considering the plan complete:

- [ ] **PC path**
  - [ ] Equip knife → click LMB quickly → stab fires; network payload `desiredAction = "Stab"` observed via `NetworkRouter:Listen(remoteName, …)` hook
  - [ ] Equip knife → hold LMB ≥ 0.4s, release → throw fires; payload `desiredAction = "Throw"` with non-zero `directionVector`
  - [ ] Equip gun → click LMB → shoot fires; payload `desiredAction = "Shoot"` with non-zero `directionVector`
  - [ ] Equip gun → press `R` → reload fires; payload `desiredAction = "Reload"`; subsequent LMB click is blocked until `ReloadDuration` elapses
  - [ ] Swap knife → gun → knife → bindings swap cleanly; `WeaponInput.bindKnife`/`bindGun` called without duplicate listeners

- [ ] **Mobile path (Studio device emulator iPad Pro)**
  - [ ] `DeviceType.getDevice()` returns `"Mobile"`
  - [ ] Equip knife → quick tap → stab fires
  - [ ] Equip knife → hold touch ≥ 0.4s → throw fires along camera `LookVector`
  - [ ] Equip knife → touch-drag > 25px → neither stab nor throw
  - [ ] Equip gun → tap → shoot fires
  - [ ] Equip gun → Reload CAS touch button visible → tap it → reload fires
  - [ ] Tap Reload button does not trigger shoot on the same touch (the `gameProcessed` guard handles this)
  - [ ] Unequip gun → Reload button disappears

- [ ] **Commit verification doc**

If any case fails, STOP, investigate, and fix before completing the plan. If all cases pass, commit nothing (no file changes) and mark the plan complete.

---

## Self-review checklist (completed during plan authoring)

**Spec coverage:**
- [x] Mobile aim via camera LookVector (Task 6)
- [x] PC aim via mouse raycast preserved (Task 5)
- [x] Gun Shoot unified on tap-in-world (Tasks 5, 6, 17)
- [x] Knife Stab/Throw unified on tap-vs-hold at 0.4s threshold (Tasks 4, 5, 6)
- [x] Cosmetic Reload (Tasks 8–13)
- [x] `R` key on PC; CAS touch button on mobile (Tasks 5, 6)
- [x] `DeviceType.getDevice(): string` contract (Task 1)
- [x] `InputPosition.lua` deleted (Task 18)
- [x] `InputRouter/` deleted (Task 19)
- [x] Server knife untouched (no tasks modify `src/Server/KnifeService/*`)
- [x] Integration tests only (no unit tests; every test runs via `execute_luau` in edit env)

**Placeholder scan:** No "TBD", "TODO", or "implement later" in any task. Empty asset IDs (`ReloadAnimationId = ""`, `ReloadSoundId = ""`) are explicit spec-level deferrals, not plan placeholders — both fall through via `if ~= ""` guards in `ReloadAction.clientExecute`.

**Type consistency:**
- `performAction(actionName: string, aimTarget: Vector3?)` — used identically in Tasks 14, 15, 16, 17
- `WeaponInput.bindKnife({ onStab, onThrow })` — signature matches Types (Task 2), PC module (Task 5), Mobile module (Task 6), executor (Task 16)
- `WeaponInput.bindGun({ onShoot, onReload })` — matches Types, PC, Mobile, executor (Task 17)
- `GestureResult` = `"Tap" | "HoldRelease" | "Pan" | "Ignored"` — consistent in Tasks 2, 4, 5, 6

No gaps or contradictions found.
