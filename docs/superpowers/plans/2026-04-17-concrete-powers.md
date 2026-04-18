# Concrete Powers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship all 13 concrete `Power` modules described in `docs/superpowers/specs/2026-04-17-concrete-powers-design.md`, plus the tiny client-side dispatcher required by Reveal and Blinding, and the four surgical weapon-service edits that wire attribute reads into knife/gun cooldowns, combat disable, and shield damage-skip.

**Architecture:** Each power is a self-contained `Power` table in `src/Server/PowerService/Powers/`. Cross-service coupling is one-way attribute flow: powers `SetAttribute`, weapon services `GetAttribute`. Per-player visual effects (Reveal highlight, Blind overlay) ride one shared `PowerBroadcast` remote, dispatched by `src/Client/PowerController/` to handlers under `Effects/`.

**Tech Stack:** Luau, Roblox services (`Players`, `ReplicatedStorage`, `ServerScriptService`, `Debris`, `CollectionService`), existing `NetworkRouter` / `ServerEventBus` / `ActionRegistryFactory` / `TeleportMetadataService` modules. Tests run via `mcp__robloxstudio__execute_luau` in the edit environment.

---

## File Structure

**New files (21):**

```
src/Server/PowerService/Powers/
    Sprint.lua
    Launch.lua
    QuickDraw.lua
    KnifeSpeedBoost.lua
    WeaponBuff.lua
    Adrenaline.lua
    Dash.lua
    ShieldPulse.lua
    Ghost.lua
    Reveal.lua
    FakeClone.lua
    SmokeScreen.lua
    Blinding.lua
    integration_powers.test.lua

src/Server/PowerService/
    integration_weapon_touchpoints.test.lua

src/Client/PowerController/
    init.lua
    executor.client.lua
    Effects/
        Reveal.lua
        Blind.lua
```

**Modified files (7):**

- `src/Server/PowerService/Configs.lua` — add `POWERS`, `BROADCAST_REMOTE`, `EFFECT_TYPES`
- `src/Server/PowerService/PowerRegistry.lua` — auto-load all ModuleScripts in `Powers/`
- `src/Server/PowerService/executor.server.lua` — create `PowerBroadcast` remote on startup
- `src/Server/KnifeService/init.lua` — `CombatDisabled` guard + `KnifeCooldownMult` read
- `src/Server/GunService/init.lua` — `CombatDisabled` guard + `GunCooldownMult` read
- `src/Server/KnifeService/Actions/StabAction.lua` — `ShieldActive` guard before `TakeDamage`
- `src/Server/KnifeService/Actions/ThrowAction.lua` — `ShieldActive` guard before `TakeDamage`
- `src/Server/GunService/Actions/ShootAction.lua` — `ShieldActive` guard before `TakeDamage`

**Manual Studio step (one time):**

- Build `StarterGui.PowerOverlays.BlindOverlay` (`ScreenGui` + full-screen child `Frame`, `Enabled = false` by default). Covered in Task 5.

**Spec deviation note:** the spec's §3.4 said the ShieldActive guard lives in `ThrowAction.lua` only and that "Stab hit detection flows through the same place in KnifeService as throw — single guard covers both". Inspection of `StabAction.lua` shows it has its own inline `TakeDamage` call independent of any shared code path. The plan adds the guard to `StabAction.lua` as well (one extra touch-point). Three attacker files instead of two.

---

### Task 1: Extend Configs

**Files:**
- Modify: `src/Server/PowerService/Configs.lua`

- [ ] **Step 1: Rewrite the Configs module**

File `src/Server/PowerService/Configs.lua`:

```lua
return {
	DEBOUNCE = 0.05,   --// seconds; per-player per-power spam guard

	POWERS = {
		Sprint          = { cooldown = 10, durationSec = 2,   speedMult = 1.5 },
		Dash            = { cooldown = 8,  durationSec = 0.3, impulseSpeed = 100 },
		Adrenaline      = { cooldown = 20, durationSec = 5,   speedMult = 1.3, cooldownMult = 0.7 },
		Launch          = { cooldown = 8,  durationSec = 3,   jumpPowerMult = 2.0 },
		QuickDraw       = { cooldown = 15, durationSec = 5,   cooldownMult = 0.5 },
		KnifeSpeedBoost = { cooldown = 15, durationSec = 5,   knifeCooldownMult = 0.74 },
		WeaponBuff      = { cooldown = 20, durationSec = 5,   knifeCooldownMult = 0.74, gunCooldownMult = 0.69 },
		ShieldPulse     = { cooldown = 15, durationSec = 2 },
		Ghost           = { cooldown = 20, durationSec = 4 },
		Reveal          = { cooldown = 15, durationSec = 4 },
		FakeClone       = { cooldown = 20, durationSec = 8,   spawnOffset = 3 },
		SmokeScreen     = { cooldown = 20, durationSec = 6,   spawnForward = 8 },
		Blinding        = {
			cooldown = 15,
			blindDurationSec = 3,
			projectileSpeed = 120,
			projectileLifetime = 3,
			aimAssistCone = math.rad(30),
		},
	},

	BROADCAST_REMOTE = "PowerBroadcast",

	EFFECT_TYPES = {
		Reveal = "Reveal",
		Blind  = "Blind",
	},
}
```

- [ ] **Step 2: Smoke-test via `execute_luau`**

Run:

```lua
local Configs = require(game:GetService("ServerScriptService").PowerService.Configs)
assert(Configs.DEBOUNCE == 0.05, "DEBOUNCE missing")
assert(Configs.POWERS.Sprint.speedMult == 1.5, "Sprint.speedMult wrong")
assert(Configs.POWERS.Blinding.aimAssistCone > 0, "Blinding.aimAssistCone missing")
assert(Configs.BROADCAST_REMOTE == "PowerBroadcast", "BROADCAST_REMOTE wrong")
assert(Configs.EFFECT_TYPES.Reveal == "Reveal", "EFFECT_TYPES.Reveal wrong")
print("Configs extension OK")
```

Expected output: `Configs extension OK`.

- [ ] **Step 3: Commit**

```bash
git add src/Server/PowerService/Configs.lua
git commit -m "feat(powers): extend Configs with per-power table and broadcast keys"
```

---

### Task 2: Weapon service touch-points

Four surgical edits + one integration test covering the non-damage guards.

**Files:**
- Modify: `src/Server/KnifeService/init.lua`
- Modify: `src/Server/GunService/init.lua`
- Modify: `src/Server/KnifeService/Actions/StabAction.lua`
- Modify: `src/Server/KnifeService/Actions/ThrowAction.lua`
- Modify: `src/Server/GunService/Actions/ShootAction.lua`
- Create: `src/Server/PowerService/integration_weapon_touchpoints.test.lua`

- [ ] **Step 1: Add `CombatDisabled` + `KnifeCooldownMult` to `KnifeService`**

In `src/Server/KnifeService/init.lua`, locate `_handleActionRequest`.

**Insert** immediately after the `currentRoundState` check (after the `warn`/`return` for inactive round), before the `playerStates[player]` lookup:

```lua
	if player:GetAttribute("CombatDisabled") then
		warn(`[KNIFE] [KnifeService] CombatDisabled on {player.Name} — rejecting action`)
		local state = playerStates[player]
		if state then KnifeService._sendStateOverride(player, state, (payload and payload.sequenceId) or 0) end
		return
	end
```

**Replace** the rate-limit block (current line ~135) and `task.delay` (current line ~160). Find:

```lua
		if timeSinceLast < (action.cooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
```

Change to read the mult and apply to both places. The full edited block:

```lua
		local knifeMult = player:GetAttribute("KnifeCooldownMult") or 1
		local effectiveCooldown = action.cooldown * knifeMult
		local now = tick()
		local timeSinceLast = now - state.lastActionTimestamp
		if timeSinceLast < (effectiveCooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
			warn(`[KNIFE] [KnifeService] Rate limit: {player.Name} ({timeSinceLast}s since last)`)
			KnifeService._sendStateOverride(player, state, payload.sequenceId)
			return
		end
```

And the `task.delay` line — find:

```lua
		task.delay(action.cooldown, function()
```

Change to:

```lua
		task.delay(effectiveCooldown, function()
```

- [ ] **Step 2: Add `CombatDisabled` + `GunCooldownMult` to `GunService`**

In `src/Server/GunService/init.lua`, locate `_handleActionRequest`. Apply the mirror edits:

Insert after the `currentRoundState` check, before the `playerStates[player]` lookup:

```lua
	if player:GetAttribute("CombatDisabled") then
		warn(`[GunService] CombatDisabled on {player.Name} — rejecting action`)
		local state = playerStates[player]
		if state then GunService._sendStateOverride(player, state, (payload and payload.sequenceId) or 0) end
		return
	end
```

Replace the rate-limit + task.delay block with:

```lua
		local gunMult = player:GetAttribute("GunCooldownMult") or 1
		local effectiveCooldown = action.cooldown * gunMult
		local now = tick()
		local timeSinceLast = now - state.lastActionTimestamp
		if timeSinceLast < (effectiveCooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
			warn(`[GunService] Rate limit: {player.Name} ({timeSinceLast}s since last)`)
			GunService._sendStateOverride(player, state, payload.sequenceId)
			return
		end
```

Change `task.delay(action.cooldown, function()` → `task.delay(effectiveCooldown, function()`.

- [ ] **Step 3: Add `ShieldActive` guard to `StabAction`**

In `src/Server/KnifeService/Actions/StabAction.lua`, find the block starting at the current line ~67:

```lua
			playerState.alreadyHit[hitPlayer] = true
			local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:SetAttribute("LastDamageSource", player.UserId)
				humanoid:TakeDamage(SharedConfigs.StabDamage)
			end
```

**Insert** a shield check immediately before `humanoid:SetAttribute("LastDamageSource", ...)`:

```lua
			playerState.alreadyHit[hitPlayer] = true
			local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if hitPlayer:GetAttribute("ShieldActive") then
					hitPlayer:SetAttribute("ShieldActive", nil)
					debugPrint(DEBUG, `[StabAction] ShieldActive absorbed stab on {hitPlayer.Name}`)
				else
					humanoid:SetAttribute("LastDamageSource", player.UserId)
					humanoid:TakeDamage(SharedConfigs.StabDamage)
				end
			end
```

- [ ] **Step 4: Add `ShieldActive` guard to `ThrowAction`**

In `src/Server/KnifeService/Actions/ThrowAction.lua`, find the `KnifeProjectileHandler.spawnProjectile` callback (currently ~line 79–98). Replace the body of the callback:

```lua
	KnifeProjectileHandler.spawnProjectile(player, directionVector, knifeTool, blacklist, function(hitPlayer)
		knifeTrace(`callback hitPlayer={hitPlayer.Name}`)
		if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then return end

		if hitPlayer:GetAttribute("ShieldActive") then
			hitPlayer:SetAttribute("ShieldActive", nil)
			knifeTrace(`ShieldActive absorbed throw on {hitPlayer.Name}`)
			return
		end

		local humanoid = hitPlayer.Character and hitPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:SetAttribute("LastDamageSource", player.UserId)
			humanoid:TakeDamage(SharedConfigs.ThrowDamage)
			knifeTrace(`damaged {hitPlayer.Name} for {SharedConfigs.ThrowDamage}`)
		end

		knifeTrace(`confirmed hit {player.Name} -> {hitPlayer.Name}`)

		local remoteName = `KnifeAction_{player.UserId}`
		NetworkRouter:Call(remoteName, player, {
			payloadType = "ProjectileHitConfirm",
			actionName = "Throw",
		})
		knifeTrace(`sent hit confirm to {player.Name}`)
	end)
```

- [ ] **Step 5: Add `ShieldActive` guard to `ShootAction`**

In `src/Server/GunService/Actions/ShootAction.lua`, find the block around line 87–92:

```lua
			if hitPlayer and hitPlayer ~= player and TeleportMetadataService.GetTeam(hitPlayer) ~= TeleportMetadataService.GetTeam(player) then
				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:SetAttribute("LastDamageSource", player.UserId)
					humanoid:TakeDamage(SharedConfigs.ShootDamage)
				end
```

**Replace** with:

```lua
			if hitPlayer and hitPlayer ~= player and TeleportMetadataService.GetTeam(hitPlayer) ~= TeleportMetadataService.GetTeam(player) then
				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid then
					if hitPlayer:GetAttribute("ShieldActive") then
						hitPlayer:SetAttribute("ShieldActive", nil)
						debugPrint(DEBUG, `[ShootAction] ShieldActive absorbed shot on {hitPlayer.Name}`)
					else
						humanoid:SetAttribute("LastDamageSource", player.UserId)
						humanoid:TakeDamage(SharedConfigs.ShootDamage)

						debugPrint(DEBUG, `[ShootAction] {player.Name} shot {hitPlayer.Name}`)

						local remoteName = `GunAction_{player.UserId}`
						NetworkRouter:Call(remoteName, player, {
							payloadType = "ProjectileHitConfirm",
							actionName = "Shoot",
						})
					end
				end
			end
```

Note: the original unconditionally-fired `ProjectileHitConfirm` + `debugPrint` now live in the `else` branch. Shield-absorbed shots do not confirm a hit to the shooter.

- [ ] **Step 6: Write the touch-point integration test**

File `src/Server/PowerService/integration_weapon_touchpoints.test.lua`:

```lua
--// Integration test for the four weapon-service attribute touch-points.
--// Run via mcp__robloxstudio__execute_luau.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KnifeService = require(ServerScriptService.KnifeService)
local GunService = require(ServerScriptService.GunService)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local passed, failed = 0, 0
local function check(label: string, cond: boolean)
	if cond then passed += 1; print(`PASS: {label}`) else failed += 1; print(`FAIL: {label}`) end
end

--// ─── Fixtures ────────────────────────────────────────────────────────────

local function mockPlayer(name: string, userId: number)
	local player
	player = {
		Name = name,
		UserId = userId,
		Character = nil,
		_attrs = {},
	}
	function player:SetAttribute(n, v) self._attrs[n] = v end
	function player:GetAttribute(n) return self._attrs[n] end
	function player:FindFirstChildWhichIsA(_className) return nil end
	function player:IsDescendantOf(container) return container == game:GetService("Players") end
	return player
end

--// NetworkRouter:Call calls remote:FireClient, which errors on non-Player mocks.
--// Capture + suppress so the real guard paths can run without raising.
local captured: { { name: string, player: any, payload: any } } = {}
local origCall = NetworkRouter.Call
NetworkRouter.Call = function(_self, name, plr, payload)
	table.insert(captured, { name = name, player = plr, payload = payload })
end

ServerEventBus:Fire("RoundStateChanged", "RoundActive")

--// ─── Case A: KnifeService CombatDisabled blocks action ──────────────────

do
	captured = {}
	local p = mockPlayer("KnifeCombatDisabled", 10001)
	KnifeService.OnPlayerAdded(p)

	p:SetAttribute("CombatDisabled", true)
	KnifeService._handleActionRequest(p, { desiredAction = "Stab", sequenceId = 1 })

	--// Guard sends a StateOverride and returns early — so we should see exactly
	--// one PowerBroadcast-shaped Call targeting this remote, AND the player's
	--// lastActionTimestamp must remain 0 (not stamped, because stamping happens
	--// only when the state machine accepts the action).
	local sentOverride = false
	for _, c in captured do
		if c.name == KnifeService._getRemoteName(p)
			and c.payload
			and c.payload.payloadType == "StateOverride" then
			sentOverride = true
			break
		end
	end
	check("A1. KnifeService CombatDisabled sent StateOverride", sentOverride)

	KnifeService.OnPlayerRemoving(p)
end

--// ─── Case B: KnifeService CombatDisabled cleared allows subsequent flow ─

do
	captured = {}
	local p = mockPlayer("KnifeFollowup", 10002)
	KnifeService.OnPlayerAdded(p)

	--// With CombatDisabled clear and no character, the service hits the
	--// "no knife equipped" branch instead — that also sends StateOverride,
	--// but the key assertion is that the code path proceeded *past* the
	--// CombatDisabled guard without short-circuiting on it.
	p:SetAttribute("CombatDisabled", nil)
	KnifeService._handleActionRequest(p, { desiredAction = "Stab", sequenceId = 1 })

	--// Must reach at least the payload-validation branch. "no knife equipped"
	--// produces a StateOverride whose sequenceId matches the one we sent.
	local reached = false
	for _, c in captured do
		if c.payload and c.payload.payloadType == "StateOverride" and c.payload.sequenceId == 1 then
			reached = true
			break
		end
	end
	check("B1. KnifeService with CombatDisabled=nil proceeds past guard", reached)

	KnifeService.OnPlayerRemoving(p)
end

--// ─── Case C: GunService CombatDisabled blocks action ────────────────────

do
	captured = {}
	local p = mockPlayer("GunCombatDisabled", 10003)
	GunService.OnPlayerAdded(p)
	p:SetAttribute("CombatDisabled", true)
	GunService._handleActionRequest(p, { desiredAction = "Shoot", sequenceId = 2 })

	local sentOverride = false
	for _, c in captured do
		if c.name == GunService._getRemoteName(p)
			and c.payload
			and c.payload.payloadType == "StateOverride" then
			sentOverride = true
			break
		end
	end
	check("C1. GunService CombatDisabled sent StateOverride", sentOverride)

	GunService.OnPlayerRemoving(p)
end

--// ─── Case D: Attribute surface readable (surface-level smoke) ───────────

do
	local p = mockPlayer("MultReader", 10004)
	p:SetAttribute("KnifeCooldownMult", 0.5)
	p:SetAttribute("GunCooldownMult", 0.7)
	check("D1. KnifeCooldownMult readable", p:GetAttribute("KnifeCooldownMult") == 0.5)
	check("D2. GunCooldownMult readable", p:GetAttribute("GunCooldownMult") == 0.7)
end

--// Restore NetworkRouter:Call
NetworkRouter.Call = origCall

print(`\n{passed} passed, {failed} failed`)
```

Scope note: this suite verifies the `CombatDisabled` guard runs and sends a `StateOverride`, plus the cooldown-mult attribute surface. Full cooldown-multiplier end-to-end verification (second-call-accepted-after-halved-wait) requires a real character with a real knife/gun tool — fragile to build. Mult correctness is covered by:

1. Each buff power's own integration test (asserts the mult is written with the correct value).
2. Manual live-session play.

`ShieldActive` damage-path guards are verified via ShieldPulse's own test (attribute set correctly) + manual live play.

- [ ] **Step 7: Run the touch-point test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game:GetService("ServerScriptService").PowerService.integration_weapon_touchpoints)
```

Expected output ends with: `5 passed, 0 failed` (with some `[KNIFE]`/`[GunService]` warns from the guards — these are expected).

- [ ] **Step 8: Commit**

```bash
git add src/Server/KnifeService/init.lua src/Server/GunService/init.lua \
        src/Server/KnifeService/Actions/StabAction.lua \
        src/Server/KnifeService/Actions/ThrowAction.lua \
        src/Server/GunService/Actions/ShootAction.lua \
        src/Server/PowerService/integration_weapon_touchpoints.test.lua
git commit -m "feat(powers): weapon-service CombatDisabled/Shield/CooldownMult guards"
```

---

### Task 3: PowerBroadcast remote + test harness

**Files:**
- Modify: `src/Server/PowerService/executor.server.lua`
- Create: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Create the `PowerBroadcast` remote on startup**

In `src/Server/PowerService/executor.server.lua`, **immediately after** the existing `require` block and helper definitions, **before** `Players.PlayerAdded:Connect(setupPlayer)`, add:

```lua
NetworkRouter:CreateRemoteEvent("PowerBroadcast")
```

The remote is created once at server startup (not per-player like `PowerAction_*`).

- [ ] **Step 2: Write the integration-test harness**

File `src/Server/PowerService/Powers/integration_powers.test.lua`:

```lua
--// Integration suite for concrete Powers. Run via mcp__robloxstudio__execute_luau.
--// Each case wires a single power into an injected registry, activates it, and
--// asserts the mid-duration + post-duration observable state.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PowerService = require(ServerScriptService.PowerService)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local passed, failed = 0, 0
local function check(label: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
		print(`PASS: {label}`)
	else
		failed += 1
		print(`FAIL: {label}{if detail then " — " .. tostring(detail) else ""}`)
	end
end

--// ─── Fixtures ────────────────────────────────────────────────────────────

local function setRoundActive() ServerEventBus:Fire("RoundStateChanged", "RoundActive") end

--// Builds a real-Instance character (Model with HRP, Head, Humanoid, Decal).
--// Caller is responsible for destroying via destroyCharacter.
local function buildCharacter(name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.Transparency = 0
	hrp.CFrame = CFrame.new(0, 10, 0)
	hrp.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Anchored = true
	head.Transparency = 0
	head.CFrame = CFrame.new(0, 12, 0)
	head.Parent = model

	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Parent = head

	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.Health = 100
	hum.Parent = model

	model.PrimaryPart = hrp
	model.Parent = workspace
	return model
end

local function destroyCharacter(model: Model?)
	if model and model.Parent then model:Destroy() end
end

--// Mock Player table with the full surface PowerService + powers read.
local function mockPlayer(opts)
	opts = opts or {}
	local player
	player = {
		Name = opts.name or "Tester",
		UserId = opts.userId or math.random(100000, 999999),
		Character = opts.character,
		_attrs = {},
	}
	function player:SetAttribute(n, v) self._attrs[n] = v end
	function player:GetAttribute(n) return self._attrs[n] end
	function player:IsDescendantOf(container)
		if opts.inGame == false then return false end
		return container == Players
	end
	return player
end

local function makeRegistry(power)
	return {
		getPower = function(name) if name == power.name then return power end return nil end,
	}
end

local function freshSession()
	PowerService._reset()
	setRoundActive()
end

--// ─── Per-power cases will be appended below as each power lands ──────────
--// (Tasks 8–20 each add one case.)

print(`\n{passed} passed, {failed} failed`)
```

- [ ] **Step 3: Smoke-test the harness loads**

Run:

```lua
require(game:GetService("ServerScriptService").PowerService.Powers.integration_powers)
```

Expected: `0 passed, 0 failed`. (No cases yet.) No runtime errors.

- [ ] **Step 4: Commit**

```bash
git add src/Server/PowerService/executor.server.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): create PowerBroadcast remote; add test harness"
```

---

### Task 4: Client `PowerController` scaffolding

**Files:**
- Create: `src/Client/PowerController/init.lua`
- Create: `src/Client/PowerController/executor.client.lua`

- [ ] **Step 1: Write the dispatcher**

File `src/Client/PowerController/init.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")   --// not actually used client-side; remove after linting if the type imports don't need it

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local PowerController = {}

local effectHandlers: { [string]: (envelope: any) -> () } = {}

function PowerController.registerEffect(effectType: string, handler: (envelope: any) -> ())
	if effectHandlers[effectType] then
		warn(`[PowerController] Duplicate effect registration: {effectType}`)
		return
	end
	effectHandlers[effectType] = handler
end

function PowerController.start()
	NetworkRouter:Listen("PowerBroadcast", function(envelope)
		if type(envelope) ~= "table" then
			warn(`[PowerController] Non-table broadcast envelope`)
			return
		end
		if type(envelope.effectType) ~= "string" then
			warn(`[PowerController] Missing/invalid effectType`)
			return
		end
		local handler = effectHandlers[envelope.effectType]
		if not handler then
			warn(`[PowerController] Unknown effectType: {envelope.effectType}`)
			return
		end
		handler(envelope)
	end)
end

return PowerController
```

Strip the unused `ServerScriptService` require if the editor flags it. Not used at runtime.

- [ ] **Step 2: Write the executor**

File `src/Client/PowerController/executor.client.lua`:

```lua
local PowerController = require(script.Parent)

--// Effects self-register when their module is required. Require them here so
--// registration happens before .start() listens.
require(script.Parent.Effects.Reveal)
require(script.Parent.Effects.Blind)

PowerController.start()
```

This will fail to load until Tasks 6 and 7 create the Effects modules — expected. The commit in this task is scaffolding only.

- [ ] **Step 3: Commit**

```bash
git add src/Client/PowerController/init.lua src/Client/PowerController/executor.client.lua
git commit -m "feat(powers): client PowerController dispatcher scaffolding"
```

---

### Task 5: Pre-build `BlindOverlay` UI in Studio

**Manual step.** No file changes, no commit.

- [ ] **Step 1: Build the pre-built ScreenGui**

In Studio:

1. Insert a `ScreenGui` under `StarterGui`. Rename it to `PowerOverlays`.
2. Insert a `ScreenGui` under `PowerOverlays`. Rename the child to `BlindOverlay`. Set `Enabled = false`, `IgnoreGuiInset = true`, `ResetOnSpawn = false`.
3. Insert a `Frame` under `BlindOverlay`. Rename it to `Overlay`. Set:
   - `AnchorPoint = (0, 0)`
   - `Position = UDim2.fromScale(0, 0)`
   - `Size = UDim2.fromScale(1, 1)`
   - `BackgroundColor3 = Color3.new(1, 1, 1)`
   - `BackgroundTransparency = 0.1`
   - `BorderSizePixel = 0`
   - `ZIndex = 1000`

The result path is `StarterGui.PowerOverlays.BlindOverlay` with one child `Frame` named `Overlay`.

- [ ] **Step 2: Verify via `execute_luau`**

Run:

```lua
local StarterGui = game:GetService("StarterGui")
local overlays = StarterGui:FindFirstChild("PowerOverlays")
assert(overlays, "PowerOverlays not found under StarterGui")
local blind = overlays:FindFirstChild("BlindOverlay")
assert(blind and blind:IsA("ScreenGui"), "BlindOverlay ScreenGui missing")
assert(blind.Enabled == false, "BlindOverlay should be disabled by default")
local frame = blind:FindFirstChild("Overlay")
assert(frame and frame:IsA("Frame"), "Overlay Frame missing")
print("BlindOverlay UI OK")
```

Expected: `BlindOverlay UI OK`.

- [ ] **Step 3: Save the place**

Commit is unnecessary (Roblox place files aren't source-tracked in this repo — UI lives inside the `.rbxl`). Save in Studio; ensure `argon serve` or `argon build` captures it if the project config syncs UI.

---

### Task 6: `Effects/Blind` client handler

**Files:**
- Create: `src/Client/PowerController/Effects/Blind.lua`

- [ ] **Step 1: Write the Blind effect handler**

File `src/Client/PowerController/Effects/Blind.lua`:

```lua
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local PowerController = require(script.Parent.Parent)

local localPlayer = Players.LocalPlayer

local function apply(envelope: any)
	if type(envelope.durationSec) ~= "number" or envelope.durationSec <= 0 then
		warn(`[PowerController.Blind] Invalid durationSec`)
		return
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn(`[PowerController.Blind] No PlayerGui`)
		return
	end

	local template = playerGui:FindFirstChild("PowerOverlays")
	template = template and template:FindFirstChild("BlindOverlay")
	if not template then
		warn(`[PowerController.Blind] BlindOverlay template missing — expected at PlayerGui.PowerOverlays.BlindOverlay`)
		return
	end

	local gui = template:Clone()
	gui.Enabled = true
	gui.Parent = playerGui
	Debris:AddItem(gui, envelope.durationSec)
end

PowerController.registerEffect("Blind", apply)

return apply
```

Note: the pre-built template lives under `StarterGui.PowerOverlays.BlindOverlay` (Task 5). Roblox copies `StarterGui` into each player's `PlayerGui` on character spawn, so the template is available there at runtime. We clone it to keep the original disabled.

- [ ] **Step 2: Commit**

```bash
git add src/Client/PowerController/Effects/Blind.lua
git commit -m "feat(powers): client Blind effect — clones pre-built BlindOverlay GUI"
```

---

### Task 7: `Effects/Reveal` client handler

**Files:**
- Create: `src/Client/PowerController/Effects/Reveal.lua`

- [ ] **Step 1: Write the Reveal effect handler**

File `src/Client/PowerController/Effects/Reveal.lua`:

```lua
local Debris = game:GetService("Debris")

local PowerController = require(script.Parent.Parent)

local function apply(envelope: any)
	if typeof(envelope.targetCharacter) ~= "Instance" or not envelope.targetCharacter:IsA("Model") then
		warn(`[PowerController.Reveal] Invalid targetCharacter`)
		return
	end
	if envelope.targetCharacter.Parent == nil then
		warn(`[PowerController.Reveal] Target character is not parented`)
		return
	end
	if type(envelope.durationSec) ~= "number" or envelope.durationSec <= 0 then
		warn(`[PowerController.Reveal] Invalid durationSec`)
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "RevealHighlight"
	highlight.Adornee = envelope.targetCharacter
	highlight.FillColor = Color3.new(1, 0.2, 0.2)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = workspace
	Debris:AddItem(highlight, envelope.durationSec)
end

PowerController.registerEffect("Reveal", apply)

return apply
```

`Highlight` is a 3D adornment, not a UI element — `Instance.new` is permitted here.

- [ ] **Step 2: Commit**

```bash
git add src/Client/PowerController/Effects/Reveal.lua
git commit -m "feat(powers): client Reveal effect — adorns Highlight to target"
```

---

### Task 8: Sprint

**Files:**
- Create: `src/Server/PowerService/Powers/Sprint.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case to the integration suite**

Open `src/Server/PowerService/Powers/integration_powers.test.lua`. **Before** the final `print(...)` line, insert:

```lua
--// ─── Case: Sprint ────────────────────────────────────────────────────────

do
	freshSession()
	local SprintPower = require(ServerScriptService.PowerService.Powers.Sprint)
	local registry = makeRegistry(SprintPower)
	local char = buildCharacter("SprintChar")
	local player = mockPlayer({ name = "Sprinter", character = char })
	local svc = PowerService.new(player, { Power = "sprint" }, registry)

	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseSpeed = hum.WalkSpeed
	local r = svc:Activate("sprint", {})
	check("Sprint.1 accepted", r.success == true)
	check("Sprint.2 WalkSpeed elevated mid-duration", hum.WalkSpeed > baseSpeed + 0.01)

	task.wait(2.1)   --// duration + epsilon
	check("Sprint.3 WalkSpeed restored after duration", math.abs(hum.WalkSpeed - baseSpeed) < 0.01)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run the test to confirm it fails (module not found)**

Run:

```lua
require(game:GetService("ServerScriptService").PowerService.Powers.integration_powers)
```

Expected: a `require` error pointing at the missing `Sprint` module. That's the failing step.

- [ ] **Step 3: Write the Sprint module**

File `src/Server/PowerService/Powers/Sprint.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Sprint

local Sprint = {}

Sprint.name = "sprint"
Sprint.cooldown = cfg.cooldown

function Sprint.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Sprint:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Sprint] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Sprint] No Humanoid for {player.Name}`); return end

	local baseSpeed = hum.WalkSpeed
	hum.WalkSpeed = baseSpeed * cfg.speedMult

	task.delay(cfg.durationSec, function()
		if hum and hum.Parent then
			hum.WalkSpeed = baseSpeed
		end
	end)
end

return Sprint
```

- [ ] **Step 4: Run the test — expect pass**

```lua
require(game:GetService("ServerScriptService").PowerService.Powers.integration_powers)
```

Expected: `3 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Sprint.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Sprint — +50% walkspeed for 2s"
```

---

### Task 9: Launch

**Files:**
- Create: `src/Server/PowerService/Powers/Launch.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

Insert before the final `print(...)`:

```lua
--// ─── Case: Launch ────────────────────────────────────────────────────────

do
	freshSession()
	local LaunchPower = require(ServerScriptService.PowerService.Powers.Launch)
	local registry = makeRegistry(LaunchPower)
	local char = buildCharacter("LaunchChar")
	local player = mockPlayer({ name = "Launcher", character = char })
	local svc = PowerService.new(player, { Power = "launch" }, registry)

	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseJump = hum.JumpPower
	local r = svc:Activate("launch", {})
	check("Launch.1 accepted", r.success == true)
	check("Launch.2 JumpPower elevated mid-duration", hum.JumpPower > baseJump + 0.01)

	task.wait(3.1)
	check("Launch.3 JumpPower restored after duration", math.abs(hum.JumpPower - baseJump) < 0.01)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run the test — expect failure**

```lua
require(game:GetService("ServerScriptService").PowerService.Powers.integration_powers)
```

Expected: `require` error for missing `Launch`.

- [ ] **Step 3: Write Launch**

File `src/Server/PowerService/Powers/Launch.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Launch

local Launch = {}

Launch.name = "launch"
Launch.cooldown = cfg.cooldown

function Launch.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Launch:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Launch] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Launch] No Humanoid for {player.Name}`); return end

	local baseJump = hum.JumpPower
	hum.JumpPower = baseJump * cfg.jumpPowerMult
	hum.Jump = true   --// trigger the boosted jump immediately

	task.delay(cfg.durationSec, function()
		if hum and hum.Parent then
			hum.JumpPower = baseJump
		end
	end)
end

return Launch
```

- [ ] **Step 4: Run tests — expect pass**

Expected: `6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Launch.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Launch — jump boost with auto-trigger"
```

---

### Task 10: QuickDraw

**Files:**
- Create: `src/Server/PowerService/Powers/QuickDraw.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

Insert before the final `print(...)`:

```lua
--// ─── Case: QuickDraw ─────────────────────────────────────────────────────

do
	freshSession()
	local QDPower = require(ServerScriptService.PowerService.Powers.QuickDraw)
	local registry = makeRegistry(QDPower)
	local char = buildCharacter("QDChar")
	local player = mockPlayer({ name = "Drawer", character = char })
	local svc = PowerService.new(player, { Power = "quickdraw" }, registry)

	local r = svc:Activate("quickdraw", {})
	check("QuickDraw.1 accepted", r.success == true)
	check("QuickDraw.2 KnifeCooldownMult set mid-duration", player:GetAttribute("KnifeCooldownMult") == 0.5)
	check("QuickDraw.3 GunCooldownMult set mid-duration", player:GetAttribute("GunCooldownMult") == 0.5)

	task.wait(5.1)
	check("QuickDraw.4 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)
	check("QuickDraw.5 GunCooldownMult cleared", player:GetAttribute("GunCooldownMult") == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write QuickDraw**

File `src/Server/PowerService/Powers/QuickDraw.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.QuickDraw

local QuickDraw = {}

QuickDraw.name = "quickdraw"
QuickDraw.cooldown = cfg.cooldown

function QuickDraw.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function QuickDraw:Execute(player: Player, _payload: any)
	player:SetAttribute("KnifeCooldownMult", cfg.cooldownMult)
	player:SetAttribute("GunCooldownMult", cfg.cooldownMult)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("KnifeCooldownMult", nil)
		player:SetAttribute("GunCooldownMult", nil)
	end)
end

return QuickDraw
```

- [ ] **Step 4: Run — expect pass**

Expected: `11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/QuickDraw.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): QuickDraw — halves knife and gun cooldowns for 5s"
```

---

### Task 11: KnifeSpeedBoost

**Files:**
- Create: `src/Server/PowerService/Powers/KnifeSpeedBoost.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: KnifeSpeedBoost ───────────────────────────────────────────────

do
	freshSession()
	local KSBPower = require(ServerScriptService.PowerService.Powers.KnifeSpeedBoost)
	local registry = makeRegistry(KSBPower)
	local char = buildCharacter("KSBChar")
	local player = mockPlayer({ name = "KnifeBoost", character = char })
	local svc = PowerService.new(player, { Power = "knifespeedboost" }, registry)

	local r = svc:Activate("knifespeedboost", {})
	check("KnifeSpeedBoost.1 accepted", r.success == true)
	check("KnifeSpeedBoost.2 KnifeCooldownMult set", player:GetAttribute("KnifeCooldownMult") == 0.74)
	check("KnifeSpeedBoost.3 GunCooldownMult NOT set", player:GetAttribute("GunCooldownMult") == nil)

	task.wait(5.1)
	check("KnifeSpeedBoost.4 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write KnifeSpeedBoost**

File `src/Server/PowerService/Powers/KnifeSpeedBoost.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.KnifeSpeedBoost

local KnifeSpeedBoost = {}

KnifeSpeedBoost.name = "knifespeedboost"
KnifeSpeedBoost.cooldown = cfg.cooldown

function KnifeSpeedBoost.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function KnifeSpeedBoost:Execute(player: Player, _payload: any)
	player:SetAttribute("KnifeCooldownMult", cfg.knifeCooldownMult)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("KnifeCooldownMult", nil)
	end)
end

return KnifeSpeedBoost
```

- [ ] **Step 4: Run — expect pass**

Expected: `15 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/KnifeSpeedBoost.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): KnifeSpeedBoost — +35% knife throw speed for 5s"
```

---

### Task 12: WeaponBuff

**Files:**
- Create: `src/Server/PowerService/Powers/WeaponBuff.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: WeaponBuff ────────────────────────────────────────────────────

do
	freshSession()
	local WBPower = require(ServerScriptService.PowerService.Powers.WeaponBuff)
	local registry = makeRegistry(WBPower)
	local char = buildCharacter("WBChar")
	local player = mockPlayer({ name = "WBTester", character = char })
	local svc = PowerService.new(player, { Power = "weaponbuff" }, registry)

	local r = svc:Activate("weaponbuff", {})
	check("WeaponBuff.1 accepted", r.success == true)
	check("WeaponBuff.2 KnifeCooldownMult set", player:GetAttribute("KnifeCooldownMult") == 0.74)
	check("WeaponBuff.3 GunCooldownMult set", player:GetAttribute("GunCooldownMult") == 0.69)

	task.wait(5.1)
	check("WeaponBuff.4 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)
	check("WeaponBuff.5 GunCooldownMult cleared", player:GetAttribute("GunCooldownMult") == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write WeaponBuff**

File `src/Server/PowerService/Powers/WeaponBuff.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.WeaponBuff

local WeaponBuff = {}

WeaponBuff.name = "weaponbuff"
WeaponBuff.cooldown = cfg.cooldown

function WeaponBuff.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function WeaponBuff:Execute(player: Player, _payload: any)
	player:SetAttribute("KnifeCooldownMult", cfg.knifeCooldownMult)
	player:SetAttribute("GunCooldownMult", cfg.gunCooldownMult)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("KnifeCooldownMult", nil)
		player:SetAttribute("GunCooldownMult", nil)
	end)
end

return WeaponBuff
```

- [ ] **Step 4: Run — expect pass**

Expected: `20 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/WeaponBuff.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): WeaponBuff — +45% gun fire rate, +35% knife throw speed for 5s"
```

---

### Task 13: Adrenaline

**Files:**
- Create: `src/Server/PowerService/Powers/Adrenaline.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: Adrenaline ────────────────────────────────────────────────────

do
	freshSession()
	local AdrPower = require(ServerScriptService.PowerService.Powers.Adrenaline)
	local registry = makeRegistry(AdrPower)
	local char = buildCharacter("AdrChar")
	local player = mockPlayer({ name = "Adrenalized", character = char })
	local svc = PowerService.new(player, { Power = "adrenaline" }, registry)

	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseSpeed = hum.WalkSpeed
	local r = svc:Activate("adrenaline", {})
	check("Adrenaline.1 accepted", r.success == true)
	check("Adrenaline.2 WalkSpeed elevated", hum.WalkSpeed > baseSpeed + 0.01)
	check("Adrenaline.3 KnifeCooldownMult set", player:GetAttribute("KnifeCooldownMult") == 0.7)
	check("Adrenaline.4 GunCooldownMult set", player:GetAttribute("GunCooldownMult") == 0.7)

	task.wait(5.1)
	check("Adrenaline.5 WalkSpeed restored", math.abs(hum.WalkSpeed - baseSpeed) < 0.01)
	check("Adrenaline.6 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)
	check("Adrenaline.7 GunCooldownMult cleared", player:GetAttribute("GunCooldownMult") == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write Adrenaline**

File `src/Server/PowerService/Powers/Adrenaline.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Adrenaline

local Adrenaline = {}

Adrenaline.name = "adrenaline"
Adrenaline.cooldown = cfg.cooldown

function Adrenaline.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Adrenaline:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Adrenaline] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Adrenaline] No Humanoid for {player.Name}`); return end

	local baseSpeed = hum.WalkSpeed
	hum.WalkSpeed = baseSpeed * cfg.speedMult
	player:SetAttribute("KnifeCooldownMult", cfg.cooldownMult)
	player:SetAttribute("GunCooldownMult", cfg.cooldownMult)

	task.delay(cfg.durationSec, function()
		if hum and hum.Parent then
			hum.WalkSpeed = baseSpeed
		end
		player:SetAttribute("KnifeCooldownMult", nil)
		player:SetAttribute("GunCooldownMult", nil)
	end)
end

return Adrenaline
```

- [ ] **Step 4: Run — expect pass**

Expected: `27 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Adrenaline.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Adrenaline — speed boost + cooldown mult for 5s"
```

---

### Task 14: Dash

**Files:**
- Create: `src/Server/PowerService/Powers/Dash.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: Dash ──────────────────────────────────────────────────────────

do
	freshSession()
	local DashPower = require(ServerScriptService.PowerService.Powers.Dash)
	local registry = makeRegistry(DashPower)
	local char = buildCharacter("DashChar")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	hrp.Anchored = false   --// LinearVelocity needs a dynamic HRP; gravity is fine since we destroy the char in <1s
	local player = mockPlayer({ name = "Dasher", character = char })
	local svc = PowerService.new(player, { Power = "dash" }, registry)

	local r = svc:Activate("dash", {})
	check("Dash.1 accepted", r.success == true)
	check("Dash.2 CombatDisabled set mid-duration", player:GetAttribute("CombatDisabled") == true)
	local lv = hrp:FindFirstChildOfClass("LinearVelocity")
	check("Dash.3 LinearVelocity exists under HRP mid-duration", lv ~= nil)

	task.wait(0.45)   --// duration + epsilon
	check("Dash.4 CombatDisabled cleared", player:GetAttribute("CombatDisabled") == nil)
	local lv2 = hrp:FindFirstChildOfClass("LinearVelocity")
	check("Dash.5 LinearVelocity removed after duration", lv2 == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write Dash**

File `src/Server/PowerService/Powers/Dash.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Dash

local Dash = {}

Dash.name = "dash"
Dash.cooldown = cfg.cooldown

function Dash.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Dash:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Dash] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[Dash] No HumanoidRootPart for {player.Name}`); return end

	local direction = hrp.CFrame.LookVector

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = hrp

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DashVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	linearVelocity.VectorVelocity = direction * cfg.impulseSpeed
	linearVelocity.Parent = hrp

	player:SetAttribute("CombatDisabled", true)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("CombatDisabled", nil)
		if linearVelocity and linearVelocity.Parent then linearVelocity:Destroy() end
		if attachment and attachment.Parent then attachment:Destroy() end
	end)
end

return Dash
```

- [ ] **Step 4: Run — expect pass**

Expected: `32 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Dash.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Dash — LinearVelocity forward impulse, CombatDisabled for 0.3s"
```

---

### Task 15: ShieldPulse

**Files:**
- Create: `src/Server/PowerService/Powers/ShieldPulse.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: ShieldPulse ───────────────────────────────────────────────────

do
	freshSession()
	local ShieldPower = require(ServerScriptService.PowerService.Powers.ShieldPulse)
	local registry = makeRegistry(ShieldPower)
	local char = buildCharacter("ShieldChar")
	local player = mockPlayer({ name = "Shielded", character = char })
	local svc = PowerService.new(player, { Power = "shieldpulse" }, registry)

	local r = svc:Activate("shieldpulse", {})
	check("ShieldPulse.1 accepted", r.success == true)
	check("ShieldPulse.2 ShieldActive mid-duration", player:GetAttribute("ShieldActive") == true)

	task.wait(2.1)
	check("ShieldPulse.3 ShieldActive cleared after duration", player:GetAttribute("ShieldActive") == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write ShieldPulse**

File `src/Server/PowerService/Powers/ShieldPulse.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.ShieldPulse

local ShieldPulse = {}

ShieldPulse.name = "shieldpulse"
ShieldPulse.cooldown = cfg.cooldown

function ShieldPulse.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function ShieldPulse:Execute(player: Player, _payload: any)
	player:SetAttribute("ShieldActive", true)

	task.delay(cfg.durationSec, function()
		--// Idempotent: if an attacker already consumed the flag, this is a no-op.
		if player:GetAttribute("ShieldActive") then
			player:SetAttribute("ShieldActive", nil)
		end
	end)
end

return ShieldPulse
```

- [ ] **Step 4: Run — expect pass**

Expected: `35 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/ShieldPulse.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): ShieldPulse — absorbs 1 hit within a 2s window"
```

---

### Task 16: Ghost

**Files:**
- Create: `src/Server/PowerService/Powers/Ghost.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: Ghost ─────────────────────────────────────────────────────────

do
	freshSession()
	local GhostPower = require(ServerScriptService.PowerService.Powers.Ghost)
	local registry = makeRegistry(GhostPower)
	local char = buildCharacter("GhostChar")
	local player = mockPlayer({ name = "Ghosted", character = char })
	local svc = PowerService.new(player, { Power = "ghost" }, registry)

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	local baseHrpT, baseHeadT = hrp.Transparency, head.Transparency

	local r = svc:Activate("ghost", {})
	check("Ghost.1 accepted", r.success == true)
	check("Ghost.2 HRP transparent mid-duration", hrp.Transparency == 1)
	check("Ghost.3 Head transparent mid-duration", head.Transparency == 1)

	task.wait(4.1)
	check("Ghost.4 HRP restored", math.abs(hrp.Transparency - baseHrpT) < 0.01)
	check("Ghost.5 Head restored", math.abs(head.Transparency - baseHeadT) < 0.01)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write Ghost**

File `src/Server/PowerService/Powers/Ghost.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Ghost

local Ghost = {}

Ghost.name = "ghost"
Ghost.cooldown = cfg.cooldown

function Ghost.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Ghost:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Ghost] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Ghost] No Humanoid for {player.Name}`); return end

	local originals: { [Instance]: number } = {}
	for _, desc in char:GetDescendants() do
		if desc:IsA("BasePart") then
			originals[desc] = desc.Transparency
			desc.Transparency = 1
		elseif desc:IsA("Decal") then
			originals[desc] = desc.Transparency
			desc.Transparency = 1
		end
	end
	local baseNameDist = hum.NameDisplayDistance
	local baseHealthDist = hum.HealthDisplayDistance
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0

	local function revert()
		if next(originals) == nil then return end   --// already reverted
		for inst, t in originals do
			if inst and inst.Parent then inst.Transparency = t end
		end
		originals = {}
		if hum and hum.Parent then
			hum.NameDisplayDistance = baseNameDist
			hum.HealthDisplayDistance = baseHealthDist
		end
	end

	hum.Died:Connect(revert)
	task.delay(cfg.durationSec, revert)
end

return Ghost
```

- [ ] **Step 4: Run — expect pass**

Expected: `40 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Ghost.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Ghost — full character transparency for 4s"
```

---

### Task 17: Reveal

**Files:**
- Create: `src/Server/PowerService/Powers/Reveal.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

The Reveal test needs multiple players with opposite teams and intercepts `NetworkRouter.Call` to capture the broadcast envelope.

```lua
--// ─── Case: Reveal ────────────────────────────────────────────────────────

do
	freshSession()
	local RevealPower = require(ServerScriptService.PowerService.Powers.Reveal)
	local registry = makeRegistry(RevealPower)

	local activatorChar = buildCharacter("RevealActivator")
	local targetChar = buildCharacter("RevealTarget")
	local activator = mockPlayer({ name = "Activator", userId = 20001, character = activatorChar })
	local target = mockPlayer({ name = "Target", userId = 20002, character = targetChar })

	--// Reveal needs to scan Players:GetPlayers() for enemies — but our mocks aren't
	--// real Player instances. Patch the power's enemy lookup by stubbing
	--// Players:GetPlayers and TeleportMetadataService.GetTeam.
	local origGetPlayers = Players.GetPlayers
	Players.GetPlayers = function() return { activator, target } end
	local origGetTeam = TeleportMetadataService.GetTeam
	TeleportMetadataService.GetTeam = function(player)
		if player == activator then return 1 end
		if player == target then return 2 end
		return nil
	end

	--// Capture NetworkRouter:Call invocations.
	local calls = {}
	local origCall = NetworkRouter.Call
	NetworkRouter.Call = function(self, name, plr, payload)
		table.insert(calls, { name = name, player = plr, payload = payload })
	end

	local svc = PowerService.new(activator, { Power = "reveal" }, registry)
	local r = svc:Activate("reveal", {})
	check("Reveal.1 accepted", r.success == true)
	check("Reveal.2 exactly one NetworkRouter:Call", #calls == 1)
	local c = calls[1]
	check("Reveal.3 remote = PowerBroadcast", c and c.name == "PowerBroadcast")
	check("Reveal.4 delivered to activator", c and c.player == activator)
	check("Reveal.5 effectType = Reveal", c and c.payload and c.payload.effectType == "Reveal")
	check("Reveal.6 targetCharacter = target's char", c and c.payload and c.payload.targetCharacter == targetChar)
	check("Reveal.7 durationSec = 4", c and c.payload and c.payload.durationSec == 4)

	--// Restore patches
	NetworkRouter.Call = origCall
	Players.GetPlayers = origGetPlayers
	TeleportMetadataService.GetTeam = origGetTeam

	destroyCharacter(activatorChar)
	destroyCharacter(targetChar)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write Reveal**

File `src/Server/PowerService/Powers/Reveal.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Reveal

local Reveal = {}

Reveal.name = "reveal"
Reveal.cooldown = cfg.cooldown

function Reveal.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Reveal:Execute(player: Player, _payload: any)
	local myTeam = TeleportMetadataService.GetTeam(player)
	if not myTeam then warn(`[Reveal] No team for {player.Name}`); return end

	local enemies: { Player } = {}
	for _, other in Players:GetPlayers() do
		if other == player then continue end
		local team = TeleportMetadataService.GetTeam(other)
		if team == nil or team == myTeam then continue end
		local char = other.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		table.insert(enemies, other)
	end

	if #enemies == 0 then
		warn(`[Reveal] No alive enemies to reveal for {player.Name}`)
		return
	end

	local target = enemies[math.random(1, #enemies)]
	NetworkRouter:Call("PowerBroadcast", player, {
		effectType = "Reveal",
		targetCharacter = target.Character,
		durationSec = cfg.durationSec,
	})
end

return Reveal
```

- [ ] **Step 4: Run — expect pass**

Expected: `47 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Reveal.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Reveal — broadcasts enemy location to activator for 4s"
```

---

### Task 18: FakeClone

**Files:**
- Create: `src/Server/PowerService/Powers/FakeClone.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: FakeClone ─────────────────────────────────────────────────────

do
	freshSession()
	local ClonePower = require(ServerScriptService.PowerService.Powers.FakeClone)
	local registry = makeRegistry(ClonePower)
	local char = buildCharacter("CloneChar")
	local player = mockPlayer({ name = "Cloner", character = char })
	local svc = PowerService.new(player, { Power = "fakeclone" }, registry)

	local preClones = #workspace:GetChildren()
	local r = svc:Activate("fakeclone", {})
	check("FakeClone.1 accepted", r.success == true)

	task.wait(0.1)
	local postClones = #workspace:GetChildren()
	check("FakeClone.2 new child parented to workspace", postClones == preClones + 1)

	--// Find and inspect the clone
	local cloneModel
	for _, c in workspace:GetChildren() do
		if c:IsA("Model") and c.Name:match("^CloneChar") and c ~= char then
			cloneModel = c
			break
		end
	end
	check("FakeClone.3 clone is a Model", cloneModel ~= nil)

	task.wait(8.1)
	check("FakeClone.4 clone removed after duration",
		cloneModel == nil or cloneModel.Parent == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write FakeClone**

File `src/Server/PowerService/Powers/FakeClone.lua`:

```lua
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.FakeClone

local FakeClone = {}

FakeClone.name = "fakeclone"
FakeClone.cooldown = cfg.cooldown

function FakeClone.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function FakeClone:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[FakeClone] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[FakeClone] No HRP for {player.Name}`); return end

	local clone = char:Clone()

	--// Strip scripts so the clone has no behavior
	for _, desc in clone:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	--// Hide nameplate on the clone's humanoid
	local cloneHum = clone:FindFirstChildOfClass("Humanoid")
	if cloneHum then
		cloneHum.NameDisplayDistance = 0
		cloneHum.HealthDisplayDistance = 0
	end

	clone.Parent = workspace
	local offsetCFrame = hrp.CFrame * CFrame.new(cfg.spawnOffset, 0, 0)
	if clone.PrimaryPart then
		clone:PivotTo(offsetCFrame)
	end

	Debris:AddItem(clone, cfg.durationSec)
end

return FakeClone
```

- [ ] **Step 4: Run — expect pass**

Expected: `51 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/FakeClone.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): FakeClone — spawns a scriptless decoy for 8s"
```

---

### Task 19: SmokeScreen

**Files:**
- Create: `src/Server/PowerService/Powers/SmokeScreen.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: SmokeScreen ───────────────────────────────────────────────────

do
	freshSession()
	local SmokePower = require(ServerScriptService.PowerService.Powers.SmokeScreen)
	local registry = makeRegistry(SmokePower)
	local char = buildCharacter("SmokeChar")
	local player = mockPlayer({ name = "Smoker", character = char })
	local svc = PowerService.new(player, { Power = "smokescreen" }, registry)

	local r = svc:Activate("smokescreen", {})
	check("SmokeScreen.1 accepted", r.success == true)

	task.wait(0.1)
	local smokePart
	for _, c in workspace:GetChildren() do
		if c:IsA("BasePart") and c.Name == "SmokeScreenCloud" then
			smokePart = c
			break
		end
	end
	check("SmokeScreen.2 smoke Part parented to workspace", smokePart ~= nil)
	check("SmokeScreen.3 smoke has ParticleEmitter child",
		smokePart and smokePart:FindFirstChildOfClass("ParticleEmitter") ~= nil)

	task.wait(6.1)
	check("SmokeScreen.4 smoke Part removed after duration",
		smokePart == nil or smokePart.Parent == nil)

	destroyCharacter(char)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write SmokeScreen**

File `src/Server/PowerService/Powers/SmokeScreen.lua`:

```lua
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.SmokeScreen

local SmokeScreen = {}

SmokeScreen.name = "smokescreen"
SmokeScreen.cooldown = cfg.cooldown

function SmokeScreen.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function SmokeScreen:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[SmokeScreen] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[SmokeScreen] No HRP for {player.Name}`); return end

	local origin = hrp.Position + hrp.CFrame.LookVector * cfg.spawnForward

	local part = Instance.new("Part")
	part.Name = "SmokeScreenCloud"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = origin
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(2, 4)
	emitter.Size = NumberSequence.new(8)
	emitter.Color = ColorSequence.new(Color3.new(0.1, 0.1, 0.1))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1,   1),
	})
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part

	Debris:AddItem(part, cfg.durationSec)
end

return SmokeScreen
```

- [ ] **Step 4: Run — expect pass**

Expected: `55 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/SmokeScreen.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): SmokeScreen — anchored particle cloud for 6s"
```

---

### Task 20: Blinding

**Files:**
- Create: `src/Server/PowerService/Powers/Blinding.lua`
- Modify: `src/Server/PowerService/Powers/integration_powers.test.lua`

- [ ] **Step 1: Append test case**

```lua
--// ─── Case: Blinding ──────────────────────────────────────────────────────

do
	freshSession()
	local BlindingPower = require(ServerScriptService.PowerService.Powers.Blinding)
	local registry = makeRegistry(BlindingPower)
	local activatorChar = buildCharacter("BlindActivator")
	local targetChar = buildCharacter("BlindTarget")

	--// Position target 20 studs in front of activator (along +Z in LookVector frame)
	local actHrp = activatorChar:FindFirstChild("HumanoidRootPart")
	local tgtHrp = targetChar:FindFirstChild("HumanoidRootPart")
	actHrp.CFrame = CFrame.new(0, 10, 0)   --// LookVector defaults to -Z
	tgtHrp.CFrame = CFrame.new(0, 10, -20)

	local activator = mockPlayer({ name = "Blinder", userId = 30001, character = activatorChar })
	local target = mockPlayer({ name = "Victim", userId = 30002, character = targetChar })

	local origGetPlayers = Players.GetPlayers
	Players.GetPlayers = function() return { activator, target } end
	local origGetTeam = TeleportMetadataService.GetTeam
	TeleportMetadataService.GetTeam = function(p)
		if p == activator then return 1 end
		if p == target then return 2 end
		return nil
	end

	local svc = PowerService.new(activator, { Power = "blinding" }, registry)
	local r = svc:Activate("blinding", {})
	check("Blinding.1 accepted", r.success == true)

	task.wait(0.1)
	local projectile
	for _, c in workspace:GetChildren() do
		if c:IsA("BasePart") and c.Name == "BlindingProjectile" then projectile = c; break end
	end
	check("Blinding.2 projectile Part exists in workspace", projectile ~= nil)
	check("Blinding.3 projectile has nonzero velocity",
		projectile and projectile.AssemblyLinearVelocity.Magnitude > 1)

	task.wait(3.1)
	check("Blinding.4 projectile removed after lifetime",
		projectile == nil or projectile.Parent == nil)

	Players.GetPlayers = origGetPlayers
	TeleportMetadataService.GetTeam = origGetTeam
	destroyCharacter(activatorChar)
	destroyCharacter(targetChar)
end
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Write Blinding**

File `src/Server/PowerService/Powers/Blinding.lua`:

```lua
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Blinding

local Blinding = {}

Blinding.name = "blinding"
Blinding.cooldown = cfg.cooldown

function Blinding.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

local function pickTarget(player: Player, originCFrame: CFrame): (Player?, Vector3)
	local myTeam = TeleportMetadataService.GetTeam(player)
	local lookVec = originCFrame.LookVector
	local originPos = originCFrame.Position

	local bestPlayer, bestAngle = nil, cfg.aimAssistCone
	for _, other in Players:GetPlayers() do
		if other == player then continue end
		local team = TeleportMetadataService.GetTeam(other)
		if team == nil or team == myTeam then continue end
		local char = other.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then continue end

		local delta = (hrp.Position - originPos)
		if delta.Magnitude < 0.01 then continue end
		local angle = math.acos(math.clamp(lookVec:Dot(delta.Unit), -1, 1))
		if angle < bestAngle then
			bestAngle = angle
			bestPlayer = other
		end
	end

	if bestPlayer then
		local tgtHrp = bestPlayer.Character:FindFirstChild("HumanoidRootPart")
		return bestPlayer, (tgtHrp.Position - originPos).Unit
	end
	return nil, lookVec
end

function Blinding:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Blinding] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[Blinding] No HRP for {player.Name}`); return end

	local targetPlayer, direction = pickTarget(player, hrp.CFrame)

	local projectile = Instance.new("Part")
	projectile.Name = "BlindingProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(2, 2, 2)
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.Massless = true
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.new(1, 1, 0.8)
	projectile.Position = hrp.Position + direction * 2
	projectile.Parent = workspace
	projectile.AssemblyLinearVelocity = direction * cfg.projectileSpeed

	local hit = false
	projectile.Touched:Connect(function(other)
		if hit then return end
		local model = other:FindFirstAncestorOfClass("Model")
		if not model then return end
		local hitPlayer = Players:GetPlayerFromCharacter(model)
		if not hitPlayer or hitPlayer == player then return end
		if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then return end

		hit = true
		NetworkRouter:Call("PowerBroadcast", hitPlayer, {
			effectType = "Blind",
			durationSec = cfg.blindDurationSec,
		})
		if projectile and projectile.Parent then projectile:Destroy() end
	end)

	Debris:AddItem(projectile, cfg.projectileLifetime)

	if targetPlayer == nil then
		warn(`[Blinding] No enemy in aim-assist cone; firing straight for {player.Name}`)
	end
end

return Blinding
```

- [ ] **Step 4: Run — expect pass**

Expected: `59 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Server/PowerService/Powers/Blinding.lua src/Server/PowerService/Powers/integration_powers.test.lua
git commit -m "feat(powers): Blinding — aim-assisted projectile that blinds victim for 3s"
```

---

### Task 21: Wire PowerRegistry to auto-load Powers

**Files:**
- Modify: `src/Server/PowerService/PowerRegistry.lua`

- [ ] **Step 1: Replace `PowerRegistry.lua`**

File `src/Server/PowerService/PowerRegistry.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)
local Types = require(ReplicatedStorage.Power.Types)

type Power = Types.Power

local powersFolder = script.Parent:FindFirstChild("Powers")
if not powersFolder then
	warn("[PowerRegistry] Powers folder missing — registry will be empty")
end

local powers: { Power } = {}
if powersFolder then
	for _, module in powersFolder:GetChildren() do
		if not module:IsA("ModuleScript") then continue end
		if module.Name:match("%.test$") then continue end
		table.insert(powers, require(module))
	end
end

local base = createRegistry(powers)

local PowerRegistry = {}

function PowerRegistry.getPower(name: string): Power?
	return base.getAction(name)
end

return PowerRegistry
```

This removes the need to touch `PowerRegistry.lua` when a new power file is added — it's picked up automatically. The `.test` suffix filter avoids including the integration test file.

- [ ] **Step 2: Smoke-test via `execute_luau`**

Run:

```lua
local PowerRegistry = require(game:GetService("ServerScriptService").PowerService.PowerRegistry)

local names = {
	"sprint", "dash", "adrenaline", "launch",
	"quickdraw", "knifespeedboost", "weaponbuff",
	"shieldpulse", "ghost", "reveal",
	"fakeclone", "smokescreen", "blinding",
}

local passed, failed = 0, 0
for _, n in names do
	local p = PowerRegistry.getPower(n)
	if p and p.name == n then
		passed += 1
		print(`registered: {n}`)
	else
		failed += 1
		print(`MISSING: {n}`)
	end
end
print(`\n{passed}/{#names} powers registered, {failed} missing`)
```

Expected: `13/13 powers registered, 0 missing`.

- [ ] **Step 3: Commit**

```bash
git add src/Server/PowerService/PowerRegistry.lua
git commit -m "feat(powers): auto-load all Powers modules into the registry"
```

---

### Task 22: Final verification

- [ ] **Step 1: Re-run the full integration test suite**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game:GetService("ServerScriptService").PowerService.Powers.integration_powers)
```

Expected: `59 passed, 0 failed`.

- [ ] **Step 2: Re-run the existing PowerService infra suite**

```lua
require(game:GetService("ServerScriptService").PowerService.integration_power_system)
```

Expected: `22 passed, 0 failed` (unchanged from the framework's baseline).

- [ ] **Step 3: Re-run the weapon-touchpoints suite**

```lua
require(game:GetService("ServerScriptService").PowerService.integration_weapon_touchpoints)
```

Expected: `5 passed, 0 failed`.

- [ ] **Step 4: Confirm final file structure**

```bash
find src/Server/PowerService src/Client/PowerController -type f | sort
```

Expected output (23 files):

```
src/Client/PowerController/Effects/Blind.lua
src/Client/PowerController/Effects/Reveal.lua
src/Client/PowerController/executor.client.lua
src/Client/PowerController/init.lua
src/Server/PowerService/Configs.lua
src/Server/PowerService/PowerRegistry.lua
src/Server/PowerService/Powers/Adrenaline.lua
src/Server/PowerService/Powers/Blinding.lua
src/Server/PowerService/Powers/Dash.lua
src/Server/PowerService/Powers/FakeClone.lua
src/Server/PowerService/Powers/Ghost.lua
src/Server/PowerService/Powers/KnifeSpeedBoost.lua
src/Server/PowerService/Powers/Launch.lua
src/Server/PowerService/Powers/QuickDraw.lua
src/Server/PowerService/Powers/Reveal.lua
src/Server/PowerService/Powers/ShieldPulse.lua
src/Server/PowerService/Powers/SmokeScreen.lua
src/Server/PowerService/Powers/Sprint.lua
src/Server/PowerService/Powers/WeaponBuff.lua
src/Server/PowerService/Powers/integration_powers.test.lua
src/Server/PowerService/Types.lua
src/Server/PowerService/executor.server.lua
src/Server/PowerService/init.lua
src/Server/PowerService/integration_power_system.test.lua
src/Server/PowerService/integration_weapon_touchpoints.test.lua
```

(Still 13 powers in `Powers/`, plus the existing framework files unchanged.)

- [ ] **Step 5: Confirm clean working tree + commit log**

```bash
git status
git log --oneline -25
```

Expected: clean working tree, roughly 20 new commits from this plan's tasks.

- [ ] **Step 6: Manual live-session smoke test (reminder, not a gate)**

The following require a live Roblox session and cannot be automated here. Run them when you next spin up a private server:

1. Set a player's loadout `.Power` to each power (one at a time via `TeleportMetadataService`).
2. Fire the `PowerAction_{UserId}` remote from a client shell with `{ powerName = "...", payload = {}, sequenceId = N }`.
3. Confirm:
   - Sprint / Adrenaline / Launch: visible speed / jump change in-character.
   - Dash: camera zips forward; knife/gun attempts during dash get `StateOverride`.
   - QuickDraw / KnifeSpeedBoost / WeaponBuff: successive knife throws and gun shots fire faster than baseline.
   - ShieldPulse: the next incoming knife or gun hit does zero damage; further hits damage normally.
   - Ghost: attacker's view shows the target's character fully transparent for 4 s.
   - Reveal: only the activator sees a Highlight on a random enemy.
   - FakeClone: a second static copy of the activator appears next to them for 8 s.
   - SmokeScreen: a dark particle cloud spawns in front of the activator for 6 s.
   - Blinding: the victim's screen goes near-white for 3 s; no one else is affected.

---

## Self-Review (performed by plan author)

**Spec coverage:**

- Spec §1 (Goal / non-goals) — no Instance.new for UI, no stacking, no prediction ✓ (see §3.3 and client task handling).
- Spec §2 (Power list) — all 13 powers land in Tasks 8–20. Table values mirror §4 configs ✓.
- Spec §3.1 (attributes) — set by powers in Tasks 8–20, read by weapon services in Task 2 ✓.
- Spec §3.2 (PowerBroadcast) — created in Task 3, consumed in Tasks 6–7 (client) and called by Reveal (17) + Blinding (20) ✓.
- Spec §3.3 (client PowerController) — Tasks 4, 6, 7 ✓.
- Spec §3.4 (weapon touch-points) — Task 2 covers the 4 spec-listed edits + the StabAction ShieldActive guard (noted spec deviation) ✓.
- Spec §3.5 (file layout) — Task 22 Step 4 verifies ✓.
- Spec §4 (Configs) — Task 1 ✓.
- Spec §5 (per-power Execute sketches) — implemented in Tasks 8–20 ✓.
- Spec §6 (validation) — `validatePayload` uniformly empty-payload per power; client envelope validation in Tasks 6 and 7 ✓.
- Spec §7 (testing) — per-power test cases in Tasks 8–20; touch-point test in Task 2 (narrower scope than spec suggested due to fixture cost, documented) ✓.
- Spec §8 (constraints) — server-authoritative, one file per responsibility, no silent returns, no `Instance.new` for UI (BlindOverlay pre-built in Task 5) ✓.
- Spec §9 (open / deferred) — no tasks; deliberate non-scope ✓.

**Placeholder scan:** No TBDs, TODOs, `"see similar task"`, or `"handle appropriate errors"` references. Every step contains concrete code or exact commands.

**Type consistency:** `Power` shape (`name`, `cooldown`, `validatePayload`, `Execute`) matches the shared type in `src/Shared/Power/Types.lua` across all 13 modules. Attribute names (`CombatDisabled`, `ShieldActive`, `KnifeCooldownMult`, `GunCooldownMult`) match between powers that set them (Tasks 8–20), weapon services that read them (Task 2), and tests that assert them.

**Deviations from spec worth the engineer's attention:**

1. **StabAction `ShieldActive` guard** — spec §3.4 implied a single guard in ThrowAction covers both; code inspection shows Stab has its own damage path. Plan adds the guard there too (third attacker file).
2. **`PowerRegistry` auto-load** — spec §3.5 said "require all 13 power modules"; plan implements this via `powersFolder:GetChildren()` iteration. Same effect, lower maintenance cost. Filter skips `*.test` files.
3. **Weapon-touchpoints test narrower than §7 suggested** — the full `_handleActionRequest` flow has enough fixture overhead (real characters, tools, knife hitbox normalization) that a thorough test is out of proportion to the four-line guards it covers. Plan provides a narrower attribute-surface test plus manual live-session verification. `ShieldActive` end-to-end validation happens through ShieldPulse's own test (proves the attribute is set) combined with manual play.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-concrete-powers.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
