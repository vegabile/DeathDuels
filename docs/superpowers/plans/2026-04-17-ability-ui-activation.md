# Ability UI Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the existing `StarterGui.AbilityUI.Frame.Button` (TextButton) and a keybind (`F` / `ButtonX`) to fire the `PowerAction_{UserId}` remote for the player's equipped power, with a cooldown display and visibility gated on equipped + alive + `RoundActive`. Implements `docs/superpowers/specs/2026-04-17-ability-ui-activation-design.md`.

**Architecture:** Server sets a replicated `EquippedPower` player attribute when `PowerService.new` resolves a loadout. Client reads that attribute (+ round state from `ClientEventBus`'s `RoundUpdate` + `Humanoid.Died`) to drive a visibility gate on the pre-built `AbilityUI` ScreenGui. Button click and keybind both call the same press handler; the client displays a local countdown for UX only — server is authoritative. `InputRouter` gains `bindPower`/`unbindPower` mirroring `bindWeapon`/`unbindWeapon`. Shared `POWERS_BY_NAME` lookup lives under `src/Shared/Power/Configs.lua` so both sides can read display names and cooldowns.

**Tech Stack:** Luau, Roblox services (`Players`, `PlayerGui`, `ContextActionService`, `Humanoid`), existing modules (`NetworkRouter`, `ClientEventBus`, `InputRouter`, `PowerService`). Server-side tests run via `mcp__robloxstudio__execute_luau`. Client UI/input behavior is verified manually.

---

## File Structure

Created in this plan:

- `src/Shared/Power/Configs.lua` — UI-facing registry → `{ displayName, cooldown }` lookup
- `src/Client/PowerController/Input/Configs.lua` — countdown update interval + safety-timeout buffer
- `src/Client/PowerController/Input/init.lua` — the button/keybind/visibility/cooldown module
- `src/Client/PowerController/executor.client.lua` — wires UI refs into `Input.init`

Modified in this plan:

- `src/Client/InputRouter/Configs.lua` — add `PowerBindings.Activate`
- `src/Client/InputRouter/init.lua` — add `bindPower` / `unbindPower`
- `src/Server/PowerService/init.lua` — set/clear `EquippedPower` player attribute
- `src/Server/PowerService/integration_power_system.test.lua` — 3 new cases for the attribute

Not touched in this plan (owned by concrete-powers):

- `src/Server/PowerService/Configs.lua` — `POWERS` table of gameplay tunings
- `src/Server/PowerService/Powers/*.lua` — concrete power modules
- `src/Client/PowerController/init.lua` / `Effects/*` — broadcast effect dispatcher

---

### Task 1: Shared POWERS_BY_NAME lookup

**Files:**
- Create: `src/Shared/Power/Configs.lua`

- [ ] **Step 1: Create the shared config module**

File `src/Shared/Power/Configs.lua`:

```lua
--// UI-facing slice shared between client and server. Gameplay-tuning fields
--// (durations, speed multipliers, particle configs, etc.) live in
--// src/Server/PowerService/Configs.lua under the concrete-powers spec.
--//
--// Table key = registryName = the Power.name set in each concrete Power module.
--// Adding a power here without a matching Power module means the UI will show
--// it but activation will fail with UnknownPower on the server — that is fine.

local POWERS_BY_NAME = {
	sprint          = { displayName = "Sprint",            cooldown = 10 },
	dash            = { displayName = "Dash",              cooldown = 8  },
	adrenaline      = { displayName = "Adrenaline",        cooldown = 20 },
	launch          = { displayName = "Launch",            cooldown = 8  },
	quickdraw       = { displayName = "Quick Draw",        cooldown = 15 },
	knifespeedboost = { displayName = "Knife Speed Boost", cooldown = 15 },
	weaponbuff      = { displayName = "Weapon Buff",       cooldown = 20 },
	shieldpulse     = { displayName = "Shield Pulse",      cooldown = 15 },
	ghost           = { displayName = "Ghost",             cooldown = 20 },
	reveal          = { displayName = "Reveal",            cooldown = 15 },
	fakeclone       = { displayName = "Fake Clone",        cooldown = 20 },
	smokescreen     = { displayName = "Smoke Screen",      cooldown = 20 },
	blinding        = { displayName = "Blinding",          cooldown = 15 },
}

return {
	POWERS_BY_NAME = POWERS_BY_NAME,
}
```

- [ ] **Step 2: Verify the module loads via Studio**

Run:

```
mcp__robloxstudio__execute_luau
  code = [[
    local cfg = require(game.ReplicatedStorage.Power.Configs)
    print(cfg.POWERS_BY_NAME.sprint.displayName)
    print(cfg.POWERS_BY_NAME.smokescreen.cooldown)
    return "ok"
  ]]
```

Expected output: `Sprint`, `20`, and `"ok"` returned. No errors.

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Power/Configs.lua
git commit -m "feat(power): add Shared.Power.Configs POWERS_BY_NAME lookup"
```

---

### Task 2: Server writes EquippedPower attribute (TDD)

**Files:**
- Modify: `src/Server/PowerService/integration_power_system.test.lua` (add 3 cases + extend mockPlayer)
- Modify: `src/Server/PowerService/init.lua`

- [ ] **Step 1: Extend the mockPlayer fixture with SetAttribute / GetAttribute**

The existing fixture at `src/Server/PowerService/integration_power_system.test.lua:37` returns a plain table; real `Instance:SetAttribute` won't work on it. Extend the fixture so the mock supports the two methods.

Locate the `mockPlayer` function (around line 37) and replace its body with:

```lua
local function mockPlayer(opts)
	opts = opts or {}
	local char, hum = mockCharacter(opts.health or 100)
	local attributes = {}
	local player
	player = {
		Name = opts.name or "Tester",
		UserId = opts.userId or 42,
		Character = char,
		IsDescendantOf = function(self, container)
			if opts.inGame == false then return false end
			return container == game:GetService("Players")
		end,
		SetAttribute = function(self, key, value)
			attributes[key] = value
		end,
		GetAttribute = function(self, key)
			return attributes[key]
		end,
	}
	return player, hum
end
```

- [ ] **Step 2: Add the three new test cases at the end of the file, before the final summary print**

Find the existing last `do ... end` test block and the summary print (`print("PASS: " .. passed, "FAIL: " .. failed)`-style). Insert these three blocks immediately before the summary:

```lua
--// ─── Case 15: EquippedPower attribute set on resolved loadout ─────────────

do
	freshSession()
	local power = makePower({ name = "testpower" })
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	PowerService.new(player, { Power = "testpower" }, registry)

	check("15. EquippedPower attribute set",
		player:GetAttribute("EquippedPower") == "testpower")
end

--// ─── Case 16: EquippedPower attribute nil when loadout missing ───────────

do
	freshSession()
	local registry = makeRegistry({})
	local player = mockPlayer()
	PowerService.new(player, nil, registry)

	check("16. EquippedPower nil on missing loadout",
		player:GetAttribute("EquippedPower") == nil)
end

--// ─── Case 17: EquippedPower cleared on :Destroy ──────────────────────────

do
	freshSession()
	local power = makePower({ name = "testpower" })
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	svc:Destroy()
	check("17. EquippedPower cleared on Destroy",
		player:GetAttribute("EquippedPower") == nil)
end
```

- [ ] **Step 3: Run the test — expect 15, 16, 17 to fail (or 15 & 17 fail)**

Run (same invocation the existing 14 cases use):

```
mcp__robloxstudio__execute_luau
  code = [[
    require(game:GetService("ServerScriptService").PowerService.integration_power_system)
    return "ran"
  ]]
```

Note the module name drops the `.test` suffix — Argon syncs `integration_power_system.test.lua` as `ServerScriptService.PowerService.integration_power_system`.

Expected: cases 15 & 17 FAIL (attribute stays nil because PowerService doesn't set it yet). Case 16 should PASS already (no loadout → attribute never set → nil, which is what we're asserting).

- [ ] **Step 4: Implement the attribute write in PowerService.new**

Open `src/Server/PowerService/init.lua`. Find the block in `PowerService.new` that resolves `self._equippedPower` (around line 39-48). Immediately after the closing `end` of the `if loadout == nil ... else ... end` block, before `instancesByPlayer[player] = self`, add:

```lua
	if self._equippedPower ~= nil then
		player:SetAttribute("EquippedPower", self._equippedPower.name)
	end
```

- [ ] **Step 5: Implement the attribute clear in PowerService:Destroy**

In the same file, find `PowerService:Destroy` (around line 58). Replace its body with:

```lua
function PowerService:Destroy()
	self.player:SetAttribute("EquippedPower", nil)
	table.clear(self._cooldowns)
	table.clear(self._lastAttempt)
	instancesByPlayer[self.player] = nil
end
```

- [ ] **Step 6: Re-run the test — expect all 17 cases to pass**

Expected output: `PASS: 17, FAIL: 0` (cases 1-14 unchanged, 15-17 now pass).

- [ ] **Step 7: Commit**

```bash
git add src/Server/PowerService/init.lua src/Server/PowerService/integration_power_system.test.lua
git commit -m "feat(power): replicate EquippedPower via player attribute"
```

---

### Task 3: Extend InputRouter with bindPower / unbindPower

**Files:**
- Modify: `src/Client/InputRouter/Configs.lua`
- Modify: `src/Client/InputRouter/init.lua`

- [ ] **Step 1: Add PowerBindings to InputRouter/Configs.lua**

Open `src/Client/InputRouter/Configs.lua`. Currently ends with `GunBindings = { ... }`. Add a new top-level field `PowerBindings` after `GunBindings`:

```lua
	PowerBindings = {
		Activate = {
			actionName  = "PowerActivate",
			keyboard    = Enum.KeyCode.F,
			gamepad     = Enum.KeyCode.ButtonX,
			touchButton = false,   --// on-screen TextButton "Button" is the touch path
		},
	},
```

Full file should now end with:

```lua
	GunBindings = {
		Shoot = {
			actionName = "GunShoot",
			mouseButton = Enum.UserInputType.MouseButton1,
			gamepad = Enum.KeyCode.ButtonR2,
			touchButton = true,
		},
	},

	PowerBindings = {
		Activate = {
			actionName  = "PowerActivate",
			keyboard    = Enum.KeyCode.F,
			gamepad     = Enum.KeyCode.ButtonX,
			touchButton = false,
		},
	},
}
```

- [ ] **Step 2: Add bindPower / unbindPower to InputRouter/init.lua**

Open `src/Client/InputRouter/init.lua`. At the end of the file, immediately before `return InputRouter`, add:

```lua
function InputRouter.bindPower(callback: () -> ())
	local binding = Configs.PowerBindings.Activate
	local inputs = {}
	if binding.keyboard then table.insert(inputs, binding.keyboard) end
	if binding.gamepad  then table.insert(inputs, binding.gamepad)  end

	ContextActionService:BindAction(
		binding.actionName,
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then return end
			callback()
		end,
		binding.touchButton,
		table.unpack(inputs)
	)

	debugPrint(DEBUG, `[InputRouter] Bound {binding.actionName}`)
end

function InputRouter.unbindPower()
	local binding = Configs.PowerBindings.Activate
	ContextActionService:UnbindAction(binding.actionName)
	debugPrint(DEBUG, `[InputRouter] Unbound {binding.actionName}`)
end
```

- [ ] **Step 3: Verify InputRouter loads**

Run:

```
mcp__robloxstudio__execute_luau
  code = [[
    local ir = require(game.StarterPlayer.StarterPlayerScripts.InputRouter)
    assert(type(ir.bindPower) == "function", "bindPower missing")
    assert(type(ir.unbindPower) == "function", "unbindPower missing")
    return "ok"
  ]]
```

Expected: `"ok"` returned, no errors.

- [ ] **Step 4: Commit**

```bash
git add src/Client/InputRouter/Configs.lua src/Client/InputRouter/init.lua
git commit -m "feat(input): add InputRouter.bindPower / unbindPower"
```

---

### Task 4: PowerController/Input/Configs.lua

**Files:**
- Create: `src/Client/PowerController/Input/Configs.lua`

- [ ] **Step 1: Create the config module**

File `src/Client/PowerController/Input/Configs.lua`:

```lua
--// Tuning for the local cooldown display + safety timeout.
--// Cooldown source of truth lives in src/Shared/Power/Configs.lua.

return {
	COOLDOWN_UPDATE_INTERVAL = 0.1,   --// seconds between button-text refreshes
	PENDING_TIMEOUT_BUFFER   = 1.0,   --// extra seconds past cooldown before the pending safety timeout fires
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Client/PowerController/Input/Configs.lua
git commit -m "feat(power): add PowerController.Input.Configs"
```

---

### Task 5: PowerController/Input/init.lua

**Files:**
- Create: `src/Client/PowerController/Input/init.lua`

- [ ] **Step 1: Create the module**

File `src/Client/PowerController/Input/init.lua`:

```lua
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientEventBus = require(script.Parent.Parent.ClientEventBus)
local InputRouter = require(script.Parent.Parent.InputRouter)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local SharedPowerConfigs = require(ReplicatedStorage.Power.Configs)

local Configs = require(script.Configs)

local Input = {}

local localPlayer = Players.LocalPlayer

local state = {
	abilityUi        = nil :: ScreenGui?,
	button           = nil :: TextButton?,
	powerName        = nil :: string?,
	powerEntry       = nil :: { displayName: string, cooldown: number }?,
	roundActive      = false,
	alive            = false,
	pendingResponse  = false,
	pendingTimeout   = nil :: thread?,
	cooldownUntil    = 0,
	cooldownThread   = nil :: thread?,
	sequenceId       = 0,
	connections      = {} :: { RBXScriptConnection | { Disconnect: (any) -> () } },
	humanoidDied     = nil :: RBXScriptConnection?,
	remoteConnection = nil :: RBXScriptConnection?,
	remoteName       = "",
	bound            = false,   --// true while the InputRouter power binding is active
	initialized      = false,
}

local function remoteName(): string
	return `PowerAction_{localPlayer.UserId}`
end

local function isOnCooldown(): boolean
	return os.clock() < state.cooldownUntil
end

local function isActivatable(): boolean
	return state.powerEntry ~= nil
		and state.roundActive
		and state.alive
		and not state.pendingResponse
		and not isOnCooldown()
end

local function updateButtonText()
	if not state.button or not state.powerEntry then return end
	local remaining = state.cooldownUntil - os.clock()
	if state.pendingResponse or remaining > 0 then
		state.button.AutoButtonColor = false
		state.button.Active = false
		local label = state.pendingResponse
			and state.powerEntry.displayName
			or string.format("%.1fs", remaining)
		state.button.Text = label
		state.button.TextTransparency = 0.4
	else
		state.button.AutoButtonColor = true
		state.button.Active = true
		state.button.Text = state.powerEntry.displayName
		state.button.TextTransparency = 0
	end
end

local function startCooldownThread()
	if state.cooldownThread then
		task.cancel(state.cooldownThread)
		state.cooldownThread = nil
	end
	state.cooldownThread = task.spawn(function()
		while os.clock() < state.cooldownUntil do
			updateButtonText()
			task.wait(Configs.COOLDOWN_UPDATE_INTERVAL)
		end
		state.cooldownThread = nil
		updateButtonText()
	end)
end

local function cancelCooldown()
	if state.cooldownThread then
		task.cancel(state.cooldownThread)
		state.cooldownThread = nil
	end
	if state.pendingTimeout then
		task.cancel(state.pendingTimeout)
		state.pendingTimeout = nil
	end
	state.cooldownUntil = 0
	state.pendingResponse = false
	updateButtonText()
end

local onActivatePressed   --// forward decl

local function refresh()
	if not state.abilityUi then return end
	local visible = state.powerEntry ~= nil
		and state.roundActive
		and state.alive
	state.abilityUi.Enabled = visible

	if visible then
		if not state.bound then
			InputRouter.bindPower(onActivatePressed)
			state.bound = true
		end
		updateButtonText()
	else
		if state.bound then
			InputRouter.unbindPower()
			state.bound = false
		end
		cancelCooldown()
	end
end

onActivatePressed = function()
	if not isActivatable() then return end
	if not state.powerName or not state.powerEntry then return end

	state.sequenceId += 1
	state.pendingResponse = true
	updateButtonText()

	--// Safety timeout: if the server response never arrives, ungrey.
	if state.pendingTimeout then task.cancel(state.pendingTimeout) end
	local thisSequence = state.sequenceId
	state.pendingTimeout = task.delay(
		state.powerEntry.cooldown + Configs.PENDING_TIMEOUT_BUFFER,
		function()
			if state.sequenceId == thisSequence and state.pendingResponse then
				warn(`[POWER] No ActivateResponse for seq={thisSequence}; ungreying`)
				state.pendingResponse = false
				state.pendingTimeout = nil
				updateButtonText()
			end
		end
	)

	NetworkRouter:Call(remoteName(), {
		powerName  = state.powerName,
		payload    = {},
		sequenceId = state.sequenceId,
	})
end

local function onServerResponse(payload: any)
	if type(payload) ~= "table" then return end
	if type(payload.sequenceId) ~= "number" then return end
	if payload.sequenceId ~= state.sequenceId then return end

	state.pendingResponse = false
	if state.pendingTimeout then
		task.cancel(state.pendingTimeout)
		state.pendingTimeout = nil
	end

	local result = payload.result
	if type(result) ~= "table" or result.success ~= true then
		updateButtonText()
		return
	end

	if not state.powerEntry then
		updateButtonText()
		return
	end

	state.cooldownUntil = os.clock() + state.powerEntry.cooldown
	startCooldownThread()
end

local function resolvePower()
	local attr = localPlayer:GetAttribute("EquippedPower")
	if attr == nil then
		state.powerName = nil
		state.powerEntry = nil
		return
	end
	if type(attr) ~= "string" then
		warn(`[POWER] EquippedPower attribute not a string: {typeof(attr)}`)
		state.powerName = nil
		state.powerEntry = nil
		return
	end
	local entry = SharedPowerConfigs.POWERS_BY_NAME[attr]
	if not entry then
		warn(`[POWER] Unknown EquippedPower: {attr}`)
		state.powerName = nil
		state.powerEntry = nil
		return
	end
	state.powerName = attr
	state.powerEntry = entry
end

local function onCharacterAdded(character: Model)
	if state.humanoidDied then
		state.humanoidDied:Disconnect()
		state.humanoidDied = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn(`[POWER] Humanoid never appeared on {character.Name}`)
		return
	end
	if humanoid.Health <= 0 then
		state.alive = false
	else
		state.alive = true
	end
	state.humanoidDied = humanoid.Died:Connect(function()
		state.alive = false
		cancelCooldown()
		refresh()
	end)
	refresh()
end

function Input.init(abilityUi: ScreenGui, button: TextButton)
	if state.initialized then return end
	state.initialized = true

	state.abilityUi = abilityUi
	state.button = button
	state.remoteName = remoteName()

	--// Hidden until we know we should show it.
	abilityUi.Enabled = false

	resolvePower()
	state.alive = localPlayer.Character ~= nil
		and localPlayer.Character:FindFirstChildOfClass("Humanoid") ~= nil
		and (localPlayer.Character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health > 0

	table.insert(state.connections, localPlayer:GetAttributeChangedSignal("EquippedPower"):Connect(function()
		cancelCooldown()
		resolvePower()
		refresh()
	end))

	table.insert(state.connections, ClientEventBus:Connect("RoundUpdate", function(snapshot)
		if type(snapshot) ~= "table" then return end
		local newState = snapshot.state
		local active = newState == RoundConfigs.GAME_STATES.RoundActive
		if active ~= state.roundActive then
			state.roundActive = active
			if not active then cancelCooldown() end
			refresh()
		end
	end))

	table.insert(state.connections, localPlayer.CharacterAdded:Connect(onCharacterAdded))
	if localPlayer.Character then onCharacterAdded(localPlayer.Character) end

	table.insert(state.connections, button.MouseButton1Click:Connect(onActivatePressed))

	state.remoteConnection = NetworkRouter:Listen(state.remoteName, onServerResponse)

	refresh()
end

function Input.destroy()
	if not state.initialized then return end
	state.initialized = false

	if state.bound then
		InputRouter.unbindPower()
		state.bound = false
	end
	cancelCooldown()
	for _, c in state.connections do c:Disconnect() end
	table.clear(state.connections)
	if state.humanoidDied then state.humanoidDied:Disconnect() state.humanoidDied = nil end
	if state.remoteConnection then state.remoteConnection:Disconnect() state.remoteConnection = nil end

	state.abilityUi = nil
	state.button = nil
	state.powerName = nil
	state.powerEntry = nil
	state.roundActive = false
	state.alive = false
	state.sequenceId = 0
	state.cooldownUntil = 0
end

return Input
```

- [ ] **Step 2: Verify the module loads**

Run:

```
mcp__robloxstudio__execute_luau
  code = [[
    local ok, err = pcall(function()
      return require(game.StarterPlayer.StarterPlayerScripts.PowerController.Input)
    end)
    if not ok then error(err) end
    return "ok"
  ]]
```

Expected: `"ok"` returned. Any require-error indicates a typo in a require path or circular dependency — fix and re-run.

- [ ] **Step 3: Commit**

```bash
git add src/Client/PowerController/Input/init.lua
git commit -m "feat(power): add PowerController.Input activation module"
```

---

### Task 6: PowerController executor

**Files:**
- Create: `src/Client/PowerController/executor.client.lua`

- [ ] **Step 1: Create the executor**

This plan owns only the `Input` portion of PowerController. When the concrete-powers plan lands, it will add a `require(script.Parent)` + `PowerController.init()` line here for the broadcast-effect dispatcher.

File `src/Client/PowerController/executor.client.lua`:

```lua
local Players = game:GetService("Players")

local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilityUi = playerGui:WaitForChild("AbilityUI")
if not abilityUi:IsA("ScreenGui") then
	warn(`[POWER] AbilityUI is {abilityUi.ClassName}, expected ScreenGui`)
	return
end

local frame = abilityUi:WaitForChild("Frame")
local button = frame:WaitForChild("Button")
if not button:IsA("TextButton") then
	warn(`[POWER] AbilityUI.Frame.Button is {button.ClassName}, expected TextButton`)
	return
end

Input.init(abilityUi, button)
```

- [ ] **Step 2: Verify executor runs in a live session**

Confirm via Studio playtest that no errors are emitted at startup. Minimal smoke-test — the next task is the full manual verification.

- [ ] **Step 3: Commit**

```bash
git add src/Client/PowerController/executor.client.lua
git commit -m "feat(power): add PowerController executor that wires AbilityUI"
```

---

### Task 7: Manual verification against a live session

**No code changes.** Run through each of these in a Studio playtest using a server that runs the full Round lifecycle (enter the place with valid teleport data so `PowerService.new` receives a resolved loadout; if no concrete Power module matches the loadout name, cases that require an actual power activation response should be skipped — the UI still must hide/show correctly and pressing the button must fire the remote).

- [ ] **Step 1: Join with a valid loadout → UI shows**

Teleport into a match. On `RoundActive`:
- `AbilityUI.Enabled == true` (visible).
- `Button.Text` equals the `displayName` from `Shared.Power.Configs.POWERS_BY_NAME[<registryName>]`.
- `Button.TextTransparency == 0`, `AutoButtonColor == true`.

If UI stays hidden: check `localPlayer:GetAttribute("EquippedPower")` returns the registry name, and that this name exists in `Shared.Power.Configs.POWERS_BY_NAME`.

- [ ] **Step 2: Press F → request fires + button greys**

Press `F`. Inspect:
- Server log shows `PowerAction_{UserId}` received (or, if no concrete power matches, the server's `PayloadValidator`/`:Activate` chain logs a rejection).
- Button immediately dims (`TextTransparency == 0.4`, `AutoButtonColor == false`).
- On successful activation: button text shows `"N.Ns"` countdown ticking down at 0.1s resolution.
- On rejection: button re-enables immediately (`AutoButtonColor == true`, text back to `displayName`).

- [ ] **Step 3: Press F during cooldown → no-op**

While countdown is visible, press `F` repeatedly. No additional remote calls should be fired (verify by server log). Click the on-screen button too — same result (`Button.Active == false` blocks the click).

- [ ] **Step 4: Gamepad `ButtonX` + touch button**

- Connect a gamepad, press `ButtonX` → same behavior as `F`.
- On a touch device (or emulator), tap the on-screen `Button` → same behavior.

- [ ] **Step 5: Die mid-cooldown → UI hides, cooldown cancels**

Activate the power, then take damage to zero HP during the cooldown. On death:
- `AbilityUI.Enabled == false` (hidden).
- After respawn in `RoundActive`: UI re-appears in ready state (no leftover countdown — local cooldown was cancelled, and the server's per-player cooldown stays but is indistinguishable from "fresh" since the button re-shows ready).

- [ ] **Step 6: Round ends mid-cooldown → UI hides**

Activate the power, then let the round end (or win) while cooldown is running. On state transition out of `RoundActive`: `AbilityUI.Enabled == false`.

- [ ] **Step 7: Safety timeout**

In Studio, temporarily stub the server handler to never respond (e.g. comment out the `fireResponse(...)` call in `PowerService/executor.server.lua` for one test run), then press `F`. After `powerEntry.cooldown + 1` seconds the button should ungrey and a warn should appear: `[POWER] No ActivateResponse for seq=...; ungreying`. Restore the server handler.

- [ ] **Step 8: Commit a short verification note only if any change was required**

If Steps 1–7 revealed a bug, fix it and commit the fix with a message describing the fix (not this plan's commit message). If everything works first-try, no commit needed.

---

## Self-Review Checklist (for the implementing engineer)

Before calling this plan done:

1. `Configs.POWERS_BY_NAME` keys in `src/Shared/Power/Configs.lua` are lowercase, no spaces, no underscores. They must match the `Power.name` set in each concrete Power module (currently unimplemented — tracked under concrete-powers).
2. `PowerService.new` writes the attribute only when `_equippedPower` is non-nil.
3. `PowerService:Destroy` writes `nil`, never a tombstone string.
4. `Input/init.lua` never reaches into `PlayerGui` or `StarterGui` — the executor does.
5. `AbilityUI.Enabled` is the only visibility mechanism. No `Parent = nil`, no `Position` tricks, no re-creating the button.
6. No `Instance.new("ScreenGui")`, `Instance.new("Frame")`, `Instance.new("TextButton")` anywhere.
7. Every `warn` carries the `[POWER]` prefix, matching existing style.
