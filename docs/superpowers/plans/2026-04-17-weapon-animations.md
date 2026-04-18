# Weapon Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire humanoid-driven cosmetic animations into the Knife and Gun systems with per-weapon profiles, marker-driven release timing, a windup-delayed gameplay model, a singleton "one animation at a time" guarantee in `AnimationController`, and a stale-callback guard so cancelled actions cannot contaminate newer ones.

**Architecture:** A new `Shared/Animations/` namespace holds the `AnimationType` enum, global animation config (marker names, fallback timings, rest-origin bound), and a pure `AnimationProfile.resolve` lookup. Existing weapon configs gain a per-`tool.Name` `AnimationProfiles` table. `AnimationController` becomes stateful (module-level `currentActiveHandle`) and returns rich handles with marker-waiting + stop signals. Client controllers capture HRP-relative rest offsets at click time, schedule release via marker-or-timeout, and dispatch remotes at release time. Server uses the client-supplied `restOrigin` for authoritative math, bounded against HRP distance. Stab becomes a real Heartbeat overlap-query hit window. Reload is a new cosmetic-only action on `R` that locks out shoot via state machine.

**Tech Stack:** Luau, Roblox services (`Players`, `ReplicatedStorage`, `ServerScriptService`, `RunService`, `ContextActionService`, `Debris`). Tests run via `mcp__robloxstudio__execute_luau` in the edit environment — no playtest, no external test runner.

**Spec reference:** `docs/superpowers/specs/2026-04-17-weapon-animations-design.md`.

---

## File Structure

**New files (5):**

```
src/Shared/Animations/
    AnimationType.lua           # frozen enum
    Configs.lua                 # marker names, default timings, rest-origin bound
    AnimationProfile.lua        # pure lookup: (toolName, profiles, type) → entry?
    AnimationProfile.test.lua   # integration test (resolve correctness)

src/Shared/Knife/
    PayloadValidator.test.lua   # integration test (restOrigin field validation)

src/Shared/Gun/
    PayloadValidator.test.lua   # integration test (restOrigin field validation)
    GunStateMachine.test.lua    # integration test (isReloading transitions)

src/Client/GunController/Actions/
    ReloadAction.lua            # new client action

src/Server/GunService/Actions/
    ReloadAction.lua            # new server action (no-op)
```

Note: the plan creates 3 test files (4 total new test files including AnimationProfile.test.lua) plus 2 new runtime files (ReloadAction client + server). Other listed items are edits.

**Modified files (17):**

- `src/Client/AnimationController.lua` — richer handle, singleton slot, `playLooped`, `playChain`, `preloadProfile`, length cache, marker listener, `stopCurrent`.
- `src/Shared/Knife/Configs.lua` — add `AnimationProfiles`, `StabHitWindow`; remove `StabAnimationId`, `ThrowAnimationId`.
- `src/Shared/Gun/Configs.lua` — add `AnimationProfiles`, `ReloadCooldown`; add `"Reload"` to `ValidActions`; remove `ShootAnimationId`.
- `src/Shared/Knife/PayloadValidator.lua` — accept `restOrigin: Vector3` on Throw; `spawnCFrame: CFrame` passthrough.
- `src/Shared/Gun/PayloadValidator.lua` — accept `restOrigin: Vector3` on Shoot.
- `src/Shared/Gun/GunStateMachine.lua` — `isReloading` field + transition rules.
- `src/Shared/Gun/Types.lua` — add `isReloading` to the state type; add `restOrigin` to payload type.
- `src/Client/KnifeController/init.lua` — generation counter, `pendingAction` record, windup/release scheduling, rest offset capture, `cancelPending`, round-state listener, weapon-active lifecycle of `stopCurrent`.
- `src/Client/GunController/init.lua` — same as above plus idle lifecycle.
- `src/Client/KnifeController/Actions/ThrowAction.lua` — release-driven projectile spawn (pulled out of `clientExecute` into a callback form).
- `src/Client/KnifeController/Actions/StabAction.lua` — trim to animation-only.
- `src/Client/GunController/Actions/ShootAction.lua` — chain LeadIn → Shoot, release-driven remote dispatch.
- `src/Client/GunController/ActionRegistry.lua` — register Reload.
- `src/Client/InputRouter/Configs.lua` — bind `R` → Reload.
- `src/Server/KnifeService/Actions/ThrowAction.lua` — consume `restOrigin`; validate `spawnCFrame`; broadcast keeps visual CFrame.
- `src/Server/KnifeService/Actions/StabAction.lua` — keep `GetPartsInPart` Heartbeat loop (existing) but scope it with `StabHitWindow`; replace `TakeDamage` with `Health = 0`; add optional supplementary `.Touched` connection feeding the same `alreadyHit` set.
- `src/Server/GunService/Actions/ShootAction.lua` — consume `restOrigin`.
- `src/Server/GunService/ActionRegistry.lua` — register Reload.

**Commit discipline:** one commit per task. Never chain tasks into a single commit — granularity is how review catches mistakes.

**Testing convention:** integration tests only. Use the existing `check(label, condition, detail?)` pass/fail pattern (see `src/Server/RoundService/TeleportDataValidator.test.lua`). Every test file starts with `--// Run via mcp__robloxstudio__execute_luau in the edit environment.` Running a test = `require(game.<Service>.<Path>["<Name>.test"])` via `mcp__robloxstudio__execute_luau`.

---

### Task 1: Create `AnimationType` enum

**Files:**
- Create: `src/Shared/Animations/AnimationType.lua`

- [ ] **Step 1: Create the enum module**

File `src/Shared/Animations/AnimationType.lua`:

```lua
--// Frozen enum of animation category keys used across weapon animation profiles.
--// Add a new entry here before referencing it from any Configs.AnimationProfiles table.
return table.freeze({
	Idle        = "Idle",
	Throw       = "Throw",
	Stab        = "Stab",
	ShootLeadIn = "ShootLeadIn",
	Shoot       = "Shoot",
	Reload      = "Reload",
})
```

- [ ] **Step 2: Verify the module loads**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local AnimationType = require(game.ReplicatedStorage.Animations.AnimationType)
print("Idle:", AnimationType.Idle)
print("Shoot:", AnimationType.Shoot)
local ok = pcall(function() AnimationType.NewKey = "nope" end)
print("frozen (should be false):", ok)
```

Expected output: `Idle: Idle`, `Shoot: Shoot`, `frozen (should be false): false`.

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Animations/AnimationType.lua
git commit -m "feat(animations): add AnimationType enum"
```

---

### Task 2: Create global Animations `Configs` module

**Files:**
- Create: `src/Shared/Animations/Configs.lua`

- [ ] **Step 1: Create the Configs module**

File `src/Shared/Animations/Configs.lua`:

```lua
--// Global animation-system configuration shared by Knife + Gun controllers.
--// Change values here to rename markers or tune fallbacks in one place.
return {
	MarkerNames = {
		Release = "Release",
	},

	--// Used when no profile.releaseTime is configured AND the marker never fires.
	DefaultReleaseTime = 0.2,

	--// Added to releaseTime as a last-resort hard timeout so a broken animation
	--// cannot lock a state machine forever.
	ReleaseTimeoutBuffer = 0.25,

	--// Server-side bound: payload.restOrigin must be within this many studs of the
	--// player's HumanoidRootPart. Catches spoofed origins from a tampered client.
	MaxRestOriginDistance = 8,
}
```

- [ ] **Step 2: Verify the module loads**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local cfg = require(game.ReplicatedStorage.Animations.Configs)
print("Release marker:", cfg.MarkerNames.Release)
print("DefaultReleaseTime:", cfg.DefaultReleaseTime)
print("MaxRestOriginDistance:", cfg.MaxRestOriginDistance)
```

Expected: `Release marker: Release`, `DefaultReleaseTime: 0.2`, `MaxRestOriginDistance: 8`.

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Animations/Configs.lua
git commit -m "feat(animations): add global animation configs"
```

---

### Task 3: Create `AnimationProfile` lookup helper

**Files:**
- Create: `src/Shared/Animations/AnimationProfile.lua`
- Test: `src/Shared/Animations/AnimationProfile.test.lua`

- [ ] **Step 1: Write the failing test**

File `src/Shared/Animations/AnimationProfile.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

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

local profiles = {
	SmallPistol = {
		[AnimationType.Idle]  = { id = "rbxassetid://111" },
		[AnimationType.Shoot] = { id = "rbxassetid://222", releaseTime = 0.1 },
	},
	Knife = {
		[AnimationType.Throw] = { id = "rbxassetid://333", releaseTime = 0.2 },
		[AnimationType.Stab]  = { id = "" },
	},
}

do
	local entry = AnimationProfile.resolve("SmallPistol", profiles, AnimationType.Idle)
	check("resolves known tool + type", entry ~= nil and entry.id == "rbxassetid://111")
end

do
	local entry = AnimationProfile.resolve("SmallPistol", profiles, AnimationType.Shoot)
	check("returns releaseTime when set", entry ~= nil and entry.releaseTime == 0.1)
end

do
	local entry = AnimationProfile.resolve("Knife", profiles, AnimationType.Stab)
	check("returns entry with blank id", entry ~= nil and entry.id == "")
	check("blank id entry has no releaseTime", entry ~= nil and entry.releaseTime == nil)
end

do
	local entry = AnimationProfile.resolve("UnknownTool", profiles, AnimationType.Idle)
	check("unknown tool returns nil", entry == nil)
end

do
	local entry = AnimationProfile.resolve("SmallPistol", profiles, "BogusType")
	check("unknown type returns nil", entry == nil)
end

do
	local entry = AnimationProfile.resolve("SmallPistol", nil :: any, AnimationType.Idle)
	check("nil profiles table returns nil", entry == nil)
end

print(`\n--- {passed} passed, {failed} failed ---`)
```

- [ ] **Step 2: Run the test to verify it fails**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Animations["AnimationProfile.test"])
```

Expected: error — `AnimationProfile` module not found.

- [ ] **Step 3: Create the implementation**

File `src/Shared/Animations/AnimationProfile.lua`:

```lua
--// Pure lookup helper. No side effects; warn+nil on unknown inputs.

export type ProfileEntry = {
	id: string,
	releaseTime: number?,
}

export type ProfileTable = { [string]: { [string]: ProfileEntry } }

local AnimationProfile = {}

function AnimationProfile.resolve(
	toolName: string,
	profiles: ProfileTable?,
	animationType: string
): ProfileEntry?
	if type(profiles) ~= "table" then
		warn(`[AnimationProfile] resolve called with non-table profiles for tool {toolName}`)
		return nil
	end

	local toolProfile = profiles[toolName]
	if not toolProfile then
		warn(`[AnimationProfile] no profile for tool {toolName}`)
		return nil
	end

	local entry = toolProfile[animationType]
	if not entry then
		warn(`[AnimationProfile] tool {toolName} has no {animationType} entry`)
		return nil
	end

	return entry
end

return AnimationProfile
```

- [ ] **Step 4: Run the test to verify it passes**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Animations["AnimationProfile.test"])
```

Expected: `--- 6 passed, 0 failed ---` (and several `warn` lines for the expected-nil cases — those are the helper warning on unknown inputs, not test failures).

- [ ] **Step 5: Commit**

```bash
git add src/Shared/Animations/AnimationProfile.lua src/Shared/Animations/AnimationProfile.test.lua
git commit -m "feat(animations): add AnimationProfile lookup helper"
```

---

### Task 4: Extend Knife Configs with `AnimationProfiles` + `StabHitWindow`

**Files:**
- Modify: `src/Shared/Knife/Configs.lua`

- [ ] **Step 1: Rewrite the Configs file**

File `src/Shared/Knife/Configs.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)

return {
	DEBUG_MODE = false,
	ValidActions = { "Stab", "Throw" },
	MaxDirectionMagnitude = 1.1,
	StabCooldown = 5,
	ThrowCooldown = 5,
	StabSoundId = "",
	ThrowSoundId = "",
	HitSoundId = "",
	StickSoundId = "",
	StabDuration = 0.5,
	ThrowDuration = 0.5,
	StabDamage = 100,
	ThrowDamage = 100,
	ThrowSpeed = 100,
	StuckDespawnTime = 5,
	ProjectileMaxLifetime = 7,

	MAX_STAB_DISTANCE = 15,

	--// Server-owned stab hit window duration in seconds. Tune to match the
	--// authored stab animation length when the ID is uploaded.
	StabHitWindow = 1.0,

	AnimationProfiles = {
		Knife = {
			[AnimationType.Throw] = { id = "rbxassetid://100789163917300", releaseTime = 0.2 },
			[AnimationType.Stab]  = { id = "" },
			[AnimationType.Idle]  = { id = "" },
		},
	},
}
```

- [ ] **Step 2: Grep for dead references to removed fields**

Search the codebase for leftover references to the removed top-level animation IDs:

```bash
# Use Grep tool: pattern "StabAnimationId|ThrowAnimationId" path "src"
```

Expected references to clean up:
- `src/Client/KnifeController/Actions/StabAction.lua` — `StabAction.animationId = SharedConfigs.StabAnimationId`
- `src/Client/KnifeController/Actions/ThrowAction.lua` — `ThrowAction.animationId = SharedConfigs.ThrowAnimationId`
- `src/Server/KnifeService/Actions/StabAction.lua` — same pattern
- `src/Server/KnifeService/Actions/ThrowAction.lua` — same pattern

These will be fully replaced in Tasks 10 / 11 / 16. For now, to keep the repo compiling after this task, update each line to pull from the new profile:

In each of the four files above, replace:

```lua
XxxAction.animationId = SharedConfigs.XxxAnimationId
```

with:

```lua
local AnimationType = require(game:GetService("ReplicatedStorage").Animations.AnimationType)
local AnimationProfile = require(game:GetService("ReplicatedStorage").Animations.AnimationProfile)
local _profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.<Type>)
XxxAction.animationId = (_profile and _profile.id) or ""
```

Use `AnimationType.Throw` / `AnimationType.Stab` as appropriate. (These reads become unused by Task 16 and get deleted then — they exist here only to keep the build green between tasks.)

- [ ] **Step 3: Verify the module loads**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local SharedConfigs = require(game.ReplicatedStorage.Knife.Configs)
print("StabHitWindow:", SharedConfigs.StabHitWindow)
print("Knife throw id:", SharedConfigs.AnimationProfiles.Knife.Throw.id)
print("StabAnimationId removed:", SharedConfigs.StabAnimationId == nil)
```

Expected: `StabHitWindow: 1`, throw id ends with `100789163917300`, `StabAnimationId removed: true`.

- [ ] **Step 4: Commit**

```bash
git add src/Shared/Knife/Configs.lua src/Client/KnifeController/Actions src/Server/KnifeService/Actions
git commit -m "feat(knife): add AnimationProfiles and StabHitWindow configs"
```

---

### Task 5: Extend Gun Configs with `AnimationProfiles`, `ReloadCooldown`, and `"Reload"` action

**Files:**
- Modify: `src/Shared/Gun/Configs.lua`

- [ ] **Step 1: Rewrite the Configs file**

File `src/Shared/Gun/Configs.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)

return {
	DEBUG_MODE = false,
	ValidActions = { "Shoot", "Reload" },
	MaxDirectionMagnitude = 1.1,
	ShootCooldown = 5,
	ReloadCooldown = 5,
	ShootDamage = 100,
	ShootSoundId = "",
	HitSoundId = "",
	ShootDuration = 0.1,
	MaxRange = 300,
	TracerDuration = 0.2,
	TracerWidth = 0.1,

	MAX_SHOOT_ORIGIN_DISTANCE = 10,

	AnimationProfiles = {
		SmallPistol = {
			[AnimationType.Idle]        = { id = "rbxassetid://86262836320062" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://109732491974921" },
			[AnimationType.Shoot]       = { id = "rbxassetid://77923963870629", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://73493786997600" },
		},
	},
}
```

- [ ] **Step 2: Grep for leftover references to `ShootAnimationId`**

Expected to find:
- `src/Client/GunController/Actions/ShootAction.lua` — `ShootAction.animationId = SharedConfigs.ShootAnimationId`
- `src/Server/GunService/Actions/ShootAction.lua` — same pattern

Update each, same treatment as Task 4 Step 2 (read from `AnimationProfiles.SmallPistol.Shoot.id` via `AnimationProfile.resolve`). Hardcode `"SmallPistol"` as the tool name for this transitional state; Task 13 / Task 14 will replace this logic with proper per-tool resolution.

- [ ] **Step 3: Verify the module loads**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local SharedConfigs = require(game.ReplicatedStorage.Gun.Configs)
print("ReloadCooldown:", SharedConfigs.ReloadCooldown)
print("Reload in ValidActions:", table.find(SharedConfigs.ValidActions, "Reload") ~= nil)
print("SmallPistol shoot id:", SharedConfigs.AnimationProfiles.SmallPistol.Shoot.id)
print("ShootAnimationId removed:", SharedConfigs.ShootAnimationId == nil)
```

Expected: `ReloadCooldown: 5`, `Reload in ValidActions: true`, shoot id ends with `77923963870629`, `ShootAnimationId removed: true`.

- [ ] **Step 4: Commit**

```bash
git add src/Shared/Gun/Configs.lua src/Client/GunController/Actions/ShootAction.lua src/Server/GunService/Actions/ShootAction.lua
git commit -m "feat(gun): add AnimationProfiles, ReloadCooldown, and Reload action slot"
```

---

### Task 6: Extend `GunStateMachine` with `isReloading`

**Files:**
- Modify: `src/Shared/Gun/GunStateMachine.lua`
- Modify: `src/Shared/Gun/Types.lua`
- Test: `src/Shared/Gun/GunStateMachine.test.lua`

- [ ] **Step 1: Write the failing test**

File `src/Shared/Gun/GunStateMachine.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)

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

do
	local s = GunStateMachine.new()
	check("initial isReloading false", s.isReloading == false)
end

do
	local s = GunStateMachine.new()
	check("Reload accepted from clear state", GunStateMachine.setActionActive(s, "Reload"))
	check("isReloading true after Reload", s.isReloading == true)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	check("Shoot rejected while reloading", not GunStateMachine.setActionActive(s, "Shoot"))
	check("isShooting stays false when rejected", s.isShooting == false)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Shoot")
	check("Reload rejected while shooting", not GunStateMachine.setActionActive(s, "Reload"))
	check("isReloading stays false when rejected", s.isReloading == false)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	GunStateMachine.resetAction(s, "Reload")
	check("isReloading false after reset", s.isReloading == false)
	check("Shoot accepted after reload reset", GunStateMachine.setActionActive(s, "Shoot"))
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	GunStateMachine.resetAll(s)
	check("resetAll clears isReloading", s.isReloading == false)
	check("resetAll clears isShooting", s.isShooting == false)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	local serialized = GunStateMachine.serialize(s)
	check("serialize includes isReloading", serialized.isReloading == true)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	check("isLocked true while reloading", GunStateMachine.isLocked(s))
end

print(`\n--- {passed} passed, {failed} failed ---`)
```

- [ ] **Step 2: Run the test to verify it fails**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Gun["GunStateMachine.test"])
```

Expected: several failures because `isReloading` doesn't exist and `"Reload"` is unknown.

- [ ] **Step 3: Update `GunStateMachine.lua`**

File `src/Shared/Gun/GunStateMachine.lua`:

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
	if state.isShooting or state.isReloading then
		return false
	end

	if actionName == "Shoot" then
		state.isShooting = true
	elseif actionName == "Reload" then
		state.isReloading = true
	else
		warn(`[GunStateMachine] Unknown action: {actionName}`)
		return false
	end

	return true
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

- [ ] **Step 4: Update `Types.lua`**

File `src/Shared/Gun/Types.lua` — replace the existing `GunStateMachine` type and `GunActionPayload` type:

```lua
export type GunStateMachine = {
	isShooting: boolean,
	isReloading: boolean,
}

export type GunActionConfig = {
	name: string,
	cooldown: number,
	duration: number,
	animationId: string,
}

--// Server actions own authoritative logic (raycast, damage, tracer)
export type ServerGunAction = GunActionConfig & {
	serverExecute: (player: Player, playerState: any, directionVector: Vector3?, restOrigin: Vector3?) -> (),
	serverCleanup: (player: Player, playerState: any) -> (),
}

--// Client actions own prediction (local tracer)
export type ClientGunAction = GunActionConfig & {
	clientExecute: (state: GunStateMachine, directionVector: Vector3?) -> (),
}

export type GunActionPayload = {
	desiredAction: string,
	directionVector: Vector3?,
	restOrigin: Vector3?,
	sequenceId: number,
}

export type ServerResponsePayload = {
	payloadType: string,
	sequenceId: number?,
	overriddenState: GunStateMachine?,
	actionName: string?,
}

export type KeybindObject = {
	userInputType: Enum.UserInputType?,
	mappedAction: string,
}

return {}
```

- [ ] **Step 5: Run the test to verify it passes**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Gun["GunStateMachine.test"])
```

Expected: `--- 11 passed, 0 failed ---`.

- [ ] **Step 6: Commit**

```bash
git add src/Shared/Gun/GunStateMachine.lua src/Shared/Gun/Types.lua src/Shared/Gun/GunStateMachine.test.lua
git commit -m "feat(gun): add isReloading to state machine"
```

---

### Task 7: Extend Knife `PayloadValidator` to accept `restOrigin`

**Files:**
- Modify: `src/Shared/Knife/PayloadValidator.lua`
- Test: `src/Shared/Knife/PayloadValidator.test.lua`

- [ ] **Step 1: Write the failing test**

File `src/Shared/Knife/PayloadValidator.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PayloadValidator = require(ReplicatedStorage.Knife.PayloadValidator)

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

local function baseThrow()
	return {
		desiredAction = "Throw",
		sequenceId = 1,
		directionVector = Vector3.new(1, 0, 0),
		restOrigin = Vector3.new(0, 5, 0),
	}
end

local function baseStab()
	return {
		desiredAction = "Stab",
		sequenceId = 1,
	}
end

do
	local ok = PayloadValidator.validate(baseThrow())
	check("valid throw with restOrigin passes", ok)
end

do
	local ok = PayloadValidator.validate(baseStab())
	check("stab without restOrigin passes", ok)
end

do
	local p = baseThrow()
	p.restOrigin = nil
	local ok, err = PayloadValidator.validate(p)
	check("throw missing restOrigin rejected", not ok)
	check("throw missing restOrigin error mentions restOrigin", ok or (err ~= nil and string.find(err, "restOrigin") ~= nil))
end

do
	local p = baseThrow()
	p.restOrigin = "not a vector"
	local ok = PayloadValidator.validate(p)
	check("throw with non-Vector3 restOrigin rejected", not ok)
end

do
	local p = baseThrow()
	p.restOrigin = Vector3.new(1, 2, 3)
	local ok = PayloadValidator.validate(p)
	check("throw with valid Vector3 restOrigin passes", ok)
end

print(`\n--- {passed} passed, {failed} failed ---`)
```

- [ ] **Step 2: Run the test to verify it fails**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Knife["PayloadValidator.test"])
```

Expected: restOrigin cases fail because the validator doesn't require it.

- [ ] **Step 3: Update the validator**

File `src/Shared/Knife/PayloadValidator.lua` — replace with:

```lua
local Configs = require(script.Parent.Configs)

local validActionSet = {}
for _, name in Configs.ValidActions do
	validActionSet[name] = true
end

--// Actions that require a restOrigin in their payload. Stab is melee and does not.
local REQUIRES_REST_ORIGIN: { [string]: boolean } = {
	Throw = true,
}

local function debugLine(message: string)
	print("[KNIFE] [PayloadValidator] " .. message)
end

local PayloadValidator = {}

function PayloadValidator.validate(payload: any): (boolean, string?)
	debugLine("validate called")
	if type(payload) ~= "table" then
		return false, "Payload is not a table"
	end

	if type(payload.desiredAction) ~= "string" then
		return false, "desiredAction is not a string"
	end

	if not validActionSet[payload.desiredAction] then
		return false, `Unknown action: {payload.desiredAction}`
	end

	if type(payload.sequenceId) ~= "number" then
		return false, "sequenceId is not a number"
	end

	if payload.sequenceId < 1 or math.floor(payload.sequenceId) ~= payload.sequenceId then
		return false, "sequenceId must be a positive integer"
	end

	if payload.directionVector ~= nil then
		if typeof(payload.directionVector) ~= "Vector3" then
			return false, "directionVector is not a Vector3"
		end
		local mag = payload.directionVector.Magnitude
		if mag < 0.1 or mag > Configs.MaxDirectionMagnitude then
			return false, `directionVector magnitude out of range: {mag}`
		end
	end

	if REQUIRES_REST_ORIGIN[payload.desiredAction] then
		if typeof(payload.restOrigin) ~= "Vector3" then
			return false, "restOrigin is required and must be a Vector3"
		end
	elseif payload.restOrigin ~= nil and typeof(payload.restOrigin) ~= "Vector3" then
		return false, "restOrigin must be a Vector3 when present"
	end

	debugLine(`payload valid action={payload.desiredAction} seq={payload.sequenceId}`)
	return true, nil
end

function PayloadValidator.normalizeDirection(directionVector: Vector3): Vector3
	return directionVector.Unit
end

return PayloadValidator
```

- [ ] **Step 4: Run the test to verify it passes**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Knife["PayloadValidator.test"])
```

Expected: `--- 6 passed, 0 failed ---`.

- [ ] **Step 5: Commit**

```bash
git add src/Shared/Knife/PayloadValidator.lua src/Shared/Knife/PayloadValidator.test.lua
git commit -m "feat(knife): validate restOrigin field on Throw payloads"
```

---

### Task 8: Extend Gun `PayloadValidator` to accept `restOrigin`

**Files:**
- Modify: `src/Shared/Gun/PayloadValidator.lua`
- Test: `src/Shared/Gun/PayloadValidator.test.lua`

- [ ] **Step 1: Write the failing test**

File `src/Shared/Gun/PayloadValidator.test.lua`:

```lua
--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PayloadValidator = require(ReplicatedStorage.Gun.PayloadValidator)

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

local function baseShoot()
	return {
		desiredAction = "Shoot",
		sequenceId = 1,
		directionVector = Vector3.new(1, 0, 0),
		restOrigin = Vector3.new(0, 5, 0),
	}
end

local function baseReload()
	return {
		desiredAction = "Reload",
		sequenceId = 1,
	}
end

do
	local ok = PayloadValidator.validate(baseShoot())
	check("valid shoot with restOrigin passes", ok)
end

do
	local ok = PayloadValidator.validate(baseReload())
	check("reload without restOrigin passes", ok)
end

do
	local p = baseShoot()
	p.restOrigin = nil
	local ok = PayloadValidator.validate(p)
	check("shoot missing restOrigin rejected", not ok)
end

do
	local p = baseShoot()
	p.restOrigin = 42
	local ok = PayloadValidator.validate(p)
	check("shoot with numeric restOrigin rejected", not ok)
end

print(`\n--- {passed} passed, {failed} failed ---`)
```

- [ ] **Step 2: Run the test to verify it fails**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Gun["PayloadValidator.test"])
```

Expected: restOrigin-required cases fail.

- [ ] **Step 3: Update the validator**

File `src/Shared/Gun/PayloadValidator.lua`:

```lua
local Configs = require(script.Parent.Configs)

local validActionSet = {}
for _, name in Configs.ValidActions do
	validActionSet[name] = true
end

local REQUIRES_REST_ORIGIN: { [string]: boolean } = {
	Shoot = true,
}

local PayloadValidator = {}

function PayloadValidator.validate(payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "Payload is not a table"
	end

	if type(payload.desiredAction) ~= "string" then
		return false, "desiredAction is not a string"
	end

	if not validActionSet[payload.desiredAction] then
		return false, `Unknown action: {payload.desiredAction}`
	end

	if type(payload.sequenceId) ~= "number" then
		return false, "sequenceId is not a number"
	end

	if payload.sequenceId < 1 or math.floor(payload.sequenceId) ~= payload.sequenceId then
		return false, "sequenceId must be a positive integer"
	end

	if payload.directionVector ~= nil then
		if typeof(payload.directionVector) ~= "Vector3" then
			return false, "directionVector is not a Vector3"
		end
		local mag = payload.directionVector.Magnitude
		if mag < 0.1 or mag > Configs.MaxDirectionMagnitude then
			return false, `directionVector magnitude out of range: {mag}`
		end
	end

	if REQUIRES_REST_ORIGIN[payload.desiredAction] then
		if typeof(payload.restOrigin) ~= "Vector3" then
			return false, "restOrigin is required and must be a Vector3"
		end
	elseif payload.restOrigin ~= nil and typeof(payload.restOrigin) ~= "Vector3" then
		return false, "restOrigin must be a Vector3 when present"
	end

	return true, nil
end

function PayloadValidator.normalizeDirection(directionVector: Vector3): Vector3
	return directionVector.Unit
end

return PayloadValidator
```

- [ ] **Step 4: Run the test to verify it passes**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game.ReplicatedStorage.Gun["PayloadValidator.test"])
```

Expected: `--- 4 passed, 0 failed ---`.

- [ ] **Step 5: Commit**

```bash
git add src/Shared/Gun/PayloadValidator.lua src/Shared/Gun/PayloadValidator.test.lua
git commit -m "feat(gun): validate restOrigin field on Shoot payloads"
```

---

### Task 9: Rewrite `AnimationController` with singleton slot and rich handle

**Files:**
- Modify: `src/Client/AnimationController.lua`

This task replaces the entire `AnimationController`. No integration test at this stage — the module requires a live `Humanoid`+`Animator` pair; it is verified in Studio via the manual check in Step 3.

- [ ] **Step 1: Rewrite `AnimationController.lua`**

File `src/Client/AnimationController.lua`:

```lua
--// AnimationController — singleton-slot animation manager for the local character.
--//
--// Invariant: at most ONE track occupies the module-level currentActiveHandle slot.
--// Any new play call stops the existing handle before starting its own track. This
--// gives the "only one animation at a time" guarantee required by weapon controllers
--// and prevents stale data from an older action contaminating a newer one.

local AnimationController = {}

export type AnimationHandle = {
	stop: () -> (),
	track: AnimationTrack?,
	waitForMarker: (name: string) -> boolean,
	stopped: RBXScriptSignal?,
}

local NOOP_HANDLE: AnimationHandle = {
	stop = function() end,
	track = nil,
	waitForMarker = function(_) return false end,
	stopped = nil,
}

--// Module-level singleton slot.
local currentActiveHandle: AnimationHandle? = nil

--// Cache of AnimationTrack.Length keyed by animationId. Populated by preloadProfile.
local lengthCache: { [string]: number } = {}

local function getAnimator(character: Model): Animator?
	return character:FindFirstChildWhichIsA("Animator", true) :: Animator?
end

local function loadTrack(character: Model, animationId: string): AnimationTrack?
	if animationId == "" then
		return nil
	end
	local animator = getAnimator(character)
	if not animator then
		warn("[AnimationController] no Animator on character")
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok then
		warn(`[AnimationController] LoadAnimation failed — {track}`)
		return nil
	end
	return track :: AnimationTrack
end

local function clearSlotIfMatches(handle: AnimationHandle)
	if currentActiveHandle == handle then
		currentActiveHandle = nil
	end
end

local function buildHandle(track: AnimationTrack): AnimationHandle
	local markerResolved: { [string]: boolean } = {}
	local handle: AnimationHandle
	handle = {
		stop = function()
			if track.IsPlaying then
				track:Stop()
			end
			clearSlotIfMatches(handle)
		end,
		track = track,
		stopped = track.Stopped,
		waitForMarker = function(name: string): boolean
			if markerResolved[name] then return false end
			local resolved = false
			local fired = false
			local co = coroutine.running()
			local markerConn
			local stoppedConn

			local function finish(result: boolean)
				if resolved then return end
				resolved = true
				markerResolved[name] = true
				if markerConn then markerConn:Disconnect() end
				if stoppedConn then stoppedConn:Disconnect() end
				fired = result
				if coroutine.status(co) == "suspended" then
					task.spawn(co)
				end
			end

			markerConn = track:GetMarkerReachedSignal(name):Connect(function()
				finish(true)
			end)
			stoppedConn = track.Stopped:Connect(function()
				finish(false)
			end)

			coroutine.yield()
			return fired
		end,
	}
	return handle
end

function AnimationController.stopCurrent()
	if currentActiveHandle then
		currentActiveHandle.stop()
	end
end

function AnimationController.play(character: Model, animationId: string): AnimationHandle
	AnimationController.stopCurrent()
	local track = loadTrack(character, animationId)
	if not track then
		return NOOP_HANDLE
	end
	local handle = buildHandle(track)
	currentActiveHandle = handle
	track:Play()
	return handle
end

function AnimationController.playLooped(character: Model, animationId: string): AnimationHandle
	AnimationController.stopCurrent()
	local track = loadTrack(character, animationId)
	if not track then
		return NOOP_HANDLE
	end
	track.Looped = true
	local handle = buildHandle(track)
	currentActiveHandle = handle
	track:Play()
	return handle
end

function AnimationController.playChain(character: Model, ids: { string }): AnimationHandle
	AnimationController.stopCurrent()
	local animator = getAnimator(character)
	if not animator then
		warn("[AnimationController] playChain — no Animator on character")
		return NOOP_HANDLE
	end

	--// Filter blanks; if none remain, no-op.
	local playable: { string } = {}
	for _, id in ids do
		if id ~= "" then table.insert(playable, id) end
	end
	if #playable == 0 then
		return NOOP_HANDLE
	end

	local chainStopped = false
	local chainHandle: AnimationHandle
	local activeTrack: AnimationTrack? = nil
	local markerResolved: { [string]: boolean } = {}

	local function stopChain()
		chainStopped = true
		if activeTrack and activeTrack.IsPlaying then
			activeTrack:Stop()
		end
		clearSlotIfMatches(chainHandle)
	end

	chainHandle = {
		stop = stopChain,
		track = nil,
		stopped = nil,
		waitForMarker = function(name: string): boolean
			if markerResolved[name] then return false end
			local resolved = false
			local fired = false
			local co = coroutine.running()
			local trackedTrack: AnimationTrack? = nil
			local markerConn
			local stoppedConn

			local function cleanup()
				if markerConn then markerConn:Disconnect() markerConn = nil end
				if stoppedConn then stoppedConn:Disconnect() stoppedConn = nil end
			end

			local function finish(result: boolean)
				if resolved then return end
				resolved = true
				markerResolved[name] = true
				cleanup()
				fired = result
				if coroutine.status(co) == "suspended" then
					task.spawn(co)
				end
			end

			local function bind(track: AnimationTrack?)
				if not track or track == trackedTrack then return end
				cleanup()
				trackedTrack = track
				markerConn = track:GetMarkerReachedSignal(name):Connect(function() finish(true) end)
			end

			--// Poll activeTrack on every Heartbeat until chain ends. Cheap: single comparison.
			local heartbeat
			heartbeat = game:GetService("RunService").Heartbeat:Connect(function()
				if resolved or chainStopped then
					heartbeat:Disconnect()
					if not resolved then finish(false) end
					return
				end
				if activeTrack ~= trackedTrack then
					bind(activeTrack)
				end
			end)

			coroutine.yield()
			heartbeat:Disconnect()
			return fired
		end,
	}

	currentActiveHandle = chainHandle

	task.spawn(function()
		for i, id in playable do
			if chainStopped then break end
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
			anim:Destroy()
			if not ok or not track then
				warn(`[AnimationController] playChain LoadAnimation failed at step {i}`)
				break
			end
			activeTrack = track
			chainHandle.track = track
			chainHandle.stopped = track.Stopped
			track:Play()
			track.Stopped:Wait()
			if chainStopped then break end
		end
		chainStopped = true
		clearSlotIfMatches(chainHandle)
	end)

	return chainHandle
end

function AnimationController.preloadProfile(
	character: Model,
	profile: { [string]: { id: string, releaseTime: number? } }
): { [string]: number }
	local animator = getAnimator(character)
	if not animator then
		warn("[AnimationController] preloadProfile — no Animator")
		return {}
	end
	local result: { [string]: number } = {}
	for _, entry in profile do
		if entry.id == "" then continue end
		if lengthCache[entry.id] then
			result[entry.id] = lengthCache[entry.id]
			continue
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = entry.id
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		anim:Destroy()
		if ok and track then
			lengthCache[entry.id] = track.Length
			result[entry.id] = track.Length
			track:Destroy()
		else
			warn(`[AnimationController] preload failed for {entry.id}`)
		end
	end
	return result
end

function AnimationController.getCachedLength(animationId: string): number?
	return lengthCache[animationId]
end

--// Retained for backwards compatibility with existing call sites.
function AnimationController.stopAll(character: Model)
	AnimationController.stopCurrent()
	local animator = getAnimator(character)
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop()
		end
	end
end

return AnimationController
```

- [ ] **Step 2: Manually verify in Studio**

Run via `mcp__robloxstudio__execute_luau` (requires a local character; easiest in Studio with the test rig spawned):

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationController = require(game.StarterPlayer.StarterPlayerScripts.AnimationController)

local char = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()

--// Play any walk animation; confirm singleton behavior by playing two in a row.
local h1 = AnimationController.play(char, "rbxassetid://507777826")
task.wait(0.5)
print("h1 playing?", h1.track and h1.track.IsPlaying)
local h2 = AnimationController.play(char, "rbxassetid://507777826")
print("h1 still playing after h2 starts?", h1.track and h1.track.IsPlaying)  --// expected: false
print("h2 playing?", h2.track and h2.track.IsPlaying)  --// expected: true
h2.stop()
```

Expected: after `h2` starts, `h1` is no longer playing. The singleton slot held one handle at a time.

- [ ] **Step 3: Commit**

```bash
git add src/Client/AnimationController.lua
git commit -m "feat(animations): singleton-slot AnimationController with markers and chain"
```

---

### Task 10: `KnifeController` — generation counter, `pendingAction` record, `cancelPending` helper

**Files:**
- Modify: `src/Client/KnifeController/init.lua`

This task adds the scaffolding without changing click-path behavior. Tasks 11 and 12 consume it.

- [ ] **Step 1: Add state fields to `KnifeController`**

At the top of `src/Client/KnifeController/init.lua`, after the existing `local safetyTimeoutThread: thread? = nil` line, add:

```lua
local pendingActionGeneration = 0
local pendingAction: {
	generation: number,
	sequenceId: number,
	actionName: string,
	restOffset: CFrame,
	handle: any,
	fallbackTimer: thread?,
	hardTimer: thread?,
}? = nil
```

- [ ] **Step 2: Add `cancelPending` helper**

Still in `src/Client/KnifeController/init.lua`, add below the state fields and above `KnifeController.onKnifeEquipped`:

```lua
local AnimationController = require(script.Parent.AnimationController)

local function cancelPending()
	pendingActionGeneration += 1
	if pendingAction then
		if pendingAction.fallbackTimer then task.cancel(pendingAction.fallbackTimer) end
		if pendingAction.hardTimer then task.cancel(pendingAction.hardTimer) end
		pendingAction = nil
	end
	AnimationController.stopCurrent()
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
	KnifeStateMachine.resetAll(stateMachine)
	knifeTrace("cancelPending executed")
end
```

(`KnifeStateMachine`, `knifeTrace`, `stateMachine`, `safetyTimeoutThread` already exist at module scope. `AnimationController` import is new if not already imported — check the top of the file; if it is, drop the duplicate `require`.)

- [ ] **Step 3: Wire `cancelPending` into lifecycle handlers**

Update `KnifeController.onKnifeUnequipped`:

```lua
function KnifeController.onKnifeUnequipped()
	knifeEquipped = false
	cancelPending()
	knifeTrace("onKnifeUnequipped")
end
```

Update `KnifeController.onPlayerDied`:

```lua
function KnifeController.onPlayerDied()
	cancelPending()
	knifeEquipped = false
end
```

In `_handleServerResponse`, inside the `StateOverride` branch, right after the `overriddenState` table check, replace the two `stateMachine.isStabbing = ...` / `stateMachine.isThrowing = ...` lines with:

```lua
cancelPending()
stateMachine.isStabbing = payload.overriddenState.isStabbing == true
stateMachine.isThrowing = payload.overriddenState.isThrowing == true
```

(The `cancelPending` call resets the machine first, then we apply the override on top — the override wins because it runs after.)

- [ ] **Step 4: Add round-state listener**

`ClientEventBus` is already imported at the top of `KnifeController/init.lua`. Add this single new import alongside the existing ones:

```lua
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
```

Then below the `KnifeController = {}` declaration, add the listener:

```lua
ClientEventBus:Connect("RoundStateChanged", function(newState: string)
	if newState ~= RoundConfigs.GAME_STATES.RoundActive then
		cancelPending()
	end
end)
```

- [ ] **Step 5: Verify the module loads**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local KnifeController = require(game.StarterPlayer.StarterPlayerScripts.KnifeController)
KnifeController.onKnifeUnequipped()  --// should print "cancelPending executed"
print("KnifeController load + cancelPending OK")
```

Expected: no errors; trace output includes `[KNIFE] cancelPending executed`.

- [ ] **Step 6: Commit**

```bash
git add src/Client/KnifeController/init.lua
git commit -m "feat(knife): add cancelPending scaffold and round-state listener"
```

---

### Task 11: `KnifeController.performAction` — windup/release scheduling

**Files:**
- Modify: `src/Client/KnifeController/init.lua`

- [ ] **Step 1: Add imports at the top of the file**

If not already present, add:

```lua
local AnimationsConfigs = require(game:GetService("ReplicatedStorage").Animations.Configs)
local AnimationType = require(game:GetService("ReplicatedStorage").Animations.AnimationType)
local AnimationProfile = require(game:GetService("ReplicatedStorage").Animations.AnimationProfile)
```

- [ ] **Step 2: Add `schedulePendingRelease` helper**

Above `KnifeController.performAction`, add:

```lua
local function schedulePendingRelease(actionName: string, profile: any, onRelease: (pending: any) -> ())
	local handle = pendingAction and pendingAction.handle
	if not handle then return end
	local capturedGen = pendingActionGeneration

	local releaseTime = (profile and profile.releaseTime) or AnimationsConfigs.DefaultReleaseTime
	local hardTimeout = releaseTime + AnimationsConfigs.ReleaseTimeoutBuffer

	local fired = false

	local function fireOnce(source: string)
		if fired then return end
		if capturedGen ~= pendingActionGeneration then
			knifeTrace(`release suppressed — stale generation (source={source})`)
			return
		end
		local snapshot = pendingAction
		if not snapshot then return end
		fired = true
		if snapshot.fallbackTimer then task.cancel(snapshot.fallbackTimer) end
		if snapshot.hardTimer then task.cancel(snapshot.hardTimer) end
		knifeTrace(`release fired action={actionName} source={source}`)
		onRelease(snapshot)
	end

	task.spawn(function()
		local markerFired = handle.waitForMarker(AnimationsConfigs.MarkerNames.Release)
		if markerFired then fireOnce("marker") end
	end)

	pendingAction.fallbackTimer = task.delay(releaseTime, function()
		fireOnce("fallback")
	end)

	pendingAction.hardTimer = task.delay(hardTimeout, function()
		if not fired then
			knifeTrace(`hard timeout fired action={actionName}`)
			fireOnce("hardtimeout")
		end
	end)
end
```

- [ ] **Step 3: Rewrite `KnifeController.performAction`**

Replace the entire existing `performAction` function with:

```lua
function KnifeController.performAction(actionName: string)
	knifeTrace(`performAction begin action={actionName} equipped={knifeEquipped} seq={sequenceId}`)
	if not knifeEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = KnifeStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		knifeTrace(`performAction blocked by state machine action={actionName}`)
		return
	end

	sequenceId += 1
	pendingActionGeneration += 1
	local thisGen = pendingActionGeneration
	local thisSeq = sequenceId

	local character = localPlayer.Character
	if not character then
		knifeTrace("performAction aborted — no character")
		KnifeStateMachine.resetAction(stateMachine, actionName)
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local knifeTool = character:FindFirstChildWhichIsA("Tool")
	local handlePart = knifeTool and knifeTool:FindFirstChild("Handle") :: BasePart?

	if not hrp or not handlePart then
		knifeTrace("performAction aborted — no HRP/handle")
		KnifeStateMachine.resetAction(stateMachine, actionName)
		return
	end

	--// Capture rest offset BEFORE starting the animation so the read is the pre-animation pose.
	local restOffset = hrp.CFrame:ToObjectSpace(handlePart.CFrame)

	local profile = AnimationProfile.resolve(
		knifeTool.Name,
		SharedConfigs.AnimationProfiles,
		actionName  --// AnimationType keys match action names for Throw/Stab
	)

	local animHandle = nil
	if profile and profile.id ~= "" then
		animHandle = AnimationController.play(character, profile.id)
	end

	pendingAction = {
		generation = thisGen,
		sequenceId = thisSeq,
		actionName = actionName,
		restOffset = restOffset,
		handle = animHandle,
		fallbackTimer = nil,
		hardTimer = nil,
	}

	--// Stab does not use the release marker — gameplay is server-owned via StabHitWindow.
	--// Throw waits for the release callback to compute direction + spawn cosmetic projectile.
	if actionName == "Throw" then
		schedulePendingRelease(actionName, profile, function(snapshot)
			if snapshot.generation ~= pendingActionGeneration then return end

			local currentChar = localPlayer.Character
			local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local currentHandle = currentChar and currentChar:FindFirstChildWhichIsA("Tool") and currentChar:FindFirstChildWhichIsA("Tool"):FindFirstChild("Handle") :: BasePart?
			if not currentHrp or not currentHandle then
				knifeTrace("release aborted — character gone")
				return
			end

			local restOrigin = (currentHrp.CFrame * snapshot.restOffset).Position
			local spawnCFrame = currentHandle.CFrame
			local aimTarget = InputPosition.getInputPosition()
			if not aimTarget then
				knifeTrace("release aborted — no aim target")
				return
			end
			local delta = aimTarget - restOrigin
			if delta.Magnitude < 0.01 then
				knifeTrace("release aborted — zero-length delta")
				return
			end
			local direction = delta.Unit

			action.clientExecute(stateMachine, direction, spawnCFrame)

			NetworkRouter:Call(remoteName, {
				desiredAction = actionName,
				directionVector = direction,
				restOrigin = restOrigin,
				spawnCFrame = spawnCFrame,
				sequenceId = snapshot.sequenceId,
			})
			knifeTrace(`Throw release sent remote seq={snapshot.sequenceId}`)
		end)
	else
		--// Stab: no release callback; fire remote immediately so the server can open its window.
		action.clientExecute(stateMachine, nil)
		NetworkRouter:Call(remoteName, {
			desiredAction = actionName,
			sequenceId = thisSeq,
		})
	end

	--// Safety timeout covers the entire windup + cooldown.
	if safetyTimeoutThread then task.cancel(safetyTimeoutThread) end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSeq then
			KnifeStateMachine.resetAction(stateMachine, actionName)
			pendingAction = nil
			knifeTrace(`safety timeout triggered action={actionName} seq={thisSeq}`)
		end
	end)
end
```

- [ ] **Step 4: Verify the module still loads**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local KnifeController = require(game.StarterPlayer.StarterPlayerScripts.KnifeController)
print("KnifeController loaded after windup refactor")
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add src/Client/KnifeController/init.lua
git commit -m "feat(knife): windup/release scheduling with generation-guarded callbacks"
```

---

### Task 12: Knife `ThrowAction` + `StabAction` client refactor

**Files:**
- Modify: `src/Client/KnifeController/Actions/ThrowAction.lua`
- Modify: `src/Client/KnifeController/Actions/StabAction.lua`

- [ ] **Step 1: Rewrite `ThrowAction.lua` (client) to accept a spawn CFrame override**

File `src/Client/KnifeController/Actions/ThrowAction.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration

do
	local profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Throw)
	ThrowAction.animationId = (profile and profile.id) or ""
end

local function getOrCreateClientFolder(): Folder
	local folderName = "ClientKnifeProjectiles"
	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = workspace
	end
	return folder
end

--// clientExecute is invoked from the release callback in KnifeController, NOT at click time.
--// directionVector is the rest-origin-computed direction; spawnCFrame is the animated visual CFrame.
function ThrowAction.clientExecute(_state, directionVector: Vector3?, spawnCFrame: CFrame?)
	if not directionVector or not spawnCFrame then return end

	local character = Players.LocalPlayer.Character
	if not character then
		warn("[KNIFE] [ClientThrowAction] no character")
		return
	end

	SFXController.playUI(SharedConfigs.ThrowSoundId)

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn("[KNIFE] [ClientThrowAction] no knife tool")
		return
	end

	local clientFolder = getOrCreateClientFolder()
	local blacklist = { character, clientFolder }
	local ignoreFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if ignoreFolder then
		table.insert(blacklist, ignoreFolder)
	end

	ProjectileFactory.spawnProjectile({
		template = knifeTool,
		directionVector = directionVector,
		spawnCFrame = spawnCFrame,
		parent = clientFolder,
		transparency = 0,
	}, Players.LocalPlayer, blacklist, nil)
end

return ThrowAction
```

- [ ] **Step 2: Simplify `StabAction.lua` (client) to sfx-only**

`KnifeController.performAction` already plays the stab animation via `AnimationController.play` using the profile ID; this file no longer needs animation handling. File `src/Client/KnifeController/Actions/StabAction.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local StabAction = {}

StabAction.name = "Stab"
StabAction.cooldown = SharedConfigs.StabCooldown
StabAction.duration = SharedConfigs.StabDuration

do
	local profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Stab)
	StabAction.animationId = (profile and profile.id) or ""
end

function StabAction.clientExecute(_state, _directionVector)
	SFXController.playUI(SharedConfigs.StabSoundId)
end

return StabAction
```

- [ ] **Step 3: Verify both files load**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ThrowAction = require(game.StarterPlayer.StarterPlayerScripts.KnifeController.Actions.ThrowAction)
local StabAction = require(game.StarterPlayer.StarterPlayerScripts.KnifeController.Actions.StabAction)
print("ThrowAction animationId:", ThrowAction.animationId)
print("StabAction animationId:", StabAction.animationId)
print("ThrowAction.clientExecute type:", type(ThrowAction.clientExecute))
```

Expected: ThrowAction id ends with `100789163917300`, StabAction id is `""`, both `clientExecute` are functions.

- [ ] **Step 4: Commit**

```bash
git add src/Client/KnifeController/Actions/ThrowAction.lua src/Client/KnifeController/Actions/StabAction.lua
git commit -m "feat(knife): release-driven throw spawn and animation-only stab client"
```

---

### Task 13: Knife server — `ThrowAction` consumes `restOrigin`

**Files:**
- Modify: `src/Server/KnifeService/Actions/ThrowAction.lua`
- Modify: `src/Server/KnifeService/init.lua`

- [ ] **Step 1: Update `KnifeService._handleActionRequest` to pass `restOrigin`**

In `src/Server/KnifeService/init.lua`, inside `_handleActionRequest`, replace the block:

```lua
local directionVector = nil
if payload.directionVector then
	directionVector = PayloadValidator.normalizeDirection(payload.directionVector)
	knifeTrace(`normalized direction for {player.Name}: {directionVector}`)
end

action.serverExecute(player, state, directionVector)
```

with:

```lua
local directionVector = nil
if payload.directionVector then
	directionVector = PayloadValidator.normalizeDirection(payload.directionVector)
end

action.serverExecute(player, state, directionVector, payload.restOrigin, payload.spawnCFrame)
```

- [ ] **Step 2: Rewrite `ThrowAction.serverExecute` to consume `restOrigin`**

File `src/Server/KnifeService/Actions/ThrowAction.lua` — replace `ThrowAction.serverExecute`:

```lua
local AnimationsConfigs = require(game:GetService("ReplicatedStorage").Animations.Configs)

function ThrowAction.serverExecute(
	player: Player,
	playerState: any,
	directionVector: Vector3?,
	restOrigin: Vector3?,
	spawnCFrame: CFrame?
)
	if not directionVector then
		warn(`[KNIFE] [ThrowAction] missing directionVector for {player.Name}`)
		return
	end
	if not restOrigin then
		warn(`[KNIFE] [ThrowAction] missing restOrigin for {player.Name}`)
		return
	end

	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	--// Distance-bound the restOrigin against HRP.
	if (restOrigin - hrp.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance then
		warn(`[KNIFE] [ThrowAction] restOrigin out of range for {player.Name}`)
		return
	end

	--// Validate spawnCFrame or fall back.
	local effectiveSpawnCFrame = spawnCFrame
	if effectiveSpawnCFrame ~= nil
		and (typeof(effectiveSpawnCFrame) ~= "CFrame"
			or (effectiveSpawnCFrame.Position - hrp.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance)
	then
		warn(`[KNIFE] [ThrowAction] spawnCFrame invalid — falling back to restOrigin`)
		effectiveSpawnCFrame = CFrame.new(restOrigin)
	elseif effectiveSpawnCFrame == nil then
		effectiveSpawnCFrame = CFrame.new(restOrigin)
	end

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn(`[KNIFE] [ThrowAction] no knife tool for {player.Name}`)
		return
	end
	playerState.lastDirection = directionVector

	local knifeFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if not knifeFolder then
		knifeFolder = Instance.new("Folder")
		knifeFolder.Name = "KnifeIgnoreFolder"
		knifeFolder.Parent = workspace
	end

	local blacklist = { character, knifeFolder }
	local clientKnifeProjectiles = workspace:FindFirstChild("ClientKnifeProjectiles")
	if clientKnifeProjectiles then
		table.insert(blacklist, clientKnifeProjectiles)
	end

	--// Broadcast to other players with effectiveSpawnCFrame for visual consistency.
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			NetworkRouter:Call("KnifeThrowBroadcast", otherPlayer, {
				throwerUserId = player.UserId,
				knifeName = knifeTool.Name,
				spawnCFrame = effectiveSpawnCFrame,
				directionVector = directionVector,
			})
		end
	end

	--// Authoritative projectile uses restOrigin as its spawn — gameplay is rest-pose-deterministic.
	local authoritativeSpawn = CFrame.new(restOrigin)

	KnifeProjectileHandler.spawnProjectile(
		player,
		directionVector,
		knifeTool,
		blacklist,
		function(hitPlayer)
			if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then return end
			local humanoid = hitPlayer.Character and hitPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:SetAttribute("LastDamageSource", player.UserId)
				humanoid:TakeDamage(SharedConfigs.ThrowDamage)
			end
			NetworkRouter:Call(`KnifeAction_{player.UserId}`, player, {
				payloadType = "ProjectileHitConfirm",
				actionName = "Throw",
			})
		end,
		authoritativeSpawn
	)
end
```

- [ ] **Step 3: Update `KnifeProjectileHandler.spawnProjectile` to accept an explicit spawn CFrame**

In `src/Server/KnifeService/KnifeProjectileHandler.lua`, change the signature and `spawnCFrame` source:

```lua
function KnifeProjectileHandler.spawnProjectile(
	player: Player,
	directionVector: Vector3,
	projectileTemplate: Instance,
	blacklistedInstancesAndDescendants: { Instance }?,
	onHit: (hitPlayer: Player) -> (),
	spawnCFrameOverride: CFrame?
)
	-- ...existing body, but replace this line:
	--   spawnCFrame = projectileTemplate.Handle.CFrame,
	-- with:
	--   spawnCFrame = spawnCFrameOverride or projectileTemplate.Handle.CFrame,
end
```

Apply exactly that substitution — everything else in the handler stays intact.

- [ ] **Step 4: Commit**

```bash
git add src/Server/KnifeService/init.lua src/Server/KnifeService/Actions/ThrowAction.lua src/Server/KnifeService/KnifeProjectileHandler.lua
git commit -m "feat(knife): server Throw consumes restOrigin with spawnCFrame fallback"
```

---

### Task 14: Knife server — `StabAction` uses `StabHitWindow` + `GetPartsInPart` + supplementary `.Touched`

**Files:**
- Modify: `src/Server/KnifeService/Actions/StabAction.lua`

- [ ] **Step 1: Rewrite `StabAction.serverExecute`**

File `src/Server/KnifeService/Actions/StabAction.lua`:

```lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)

local ServerConfigs = require(script.Parent.Parent.Configs)
local TeleportMetadataService = require(script.Parent.Parent.Parent.RoundService.TeleportMetadataService)
local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local StabAction = {}

StabAction.name = "Stab"
StabAction.cooldown = SharedConfigs.StabCooldown
StabAction.duration = SharedConfigs.StabDuration

do
	local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
	local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
	local profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Stab)
	StabAction.animationId = (profile and profile.id) or ""
end

local function processHitPlayer(attacker: Player, playerState: any, hitPlayer: Player?, hitCharacter: Model?)
	if not hitPlayer or not hitCharacter then return end
	if hitPlayer == attacker then return end
	if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(attacker) then return end
	if playerState.alreadyHit[hitPlayer] then return end

	local attackerChar = attacker.Character
	local attackerRoot = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local victimRoot = hitCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if attackerRoot and victimRoot and (attackerRoot.Position - victimRoot.Position).Magnitude > SharedConfigs.MAX_STAB_DISTANCE then
		return
	end

	playerState.alreadyHit[hitPlayer] = true
	local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute("LastDamageSource", attacker.UserId)
		humanoid.Health = 0
	end
	debugPrint(DEBUG, `[StabAction] {attacker.Name} killed {hitPlayer.Name}`)
end

function StabAction.serverExecute(player: Player, playerState: any, _directionVector: Vector3?)
	playerState.alreadyHit = {}
	local startTime = tick()

	local character = player.Character
	if not character then return end
	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then return end
	local hitbox = knifeTool:FindFirstChild("Hitbox") :: BasePart?
	if not hitbox then return end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	--// Primary detection: Heartbeat overlap query for the full window.
	local heartbeatConn: RBXScriptConnection? = nil
	local touchedConn: RBXScriptConnection? = nil

	local function tearDown()
		if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
		if touchedConn then touchedConn:Disconnect() touchedConn = nil end
		playerState.alreadyHit = {}
		playerState.currentTickConnection = nil
	end

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if tick() - startTime >= SharedConfigs.StabHitWindow then
			tearDown()
			return
		end

		local currentChar = player.Character
		if not currentChar then return end
		local currentTool = KnifeUtility.findKnifeTool(currentChar)
		if not currentTool then return end
		local currentHitbox = currentTool:FindFirstChild("Hitbox") :: BasePart?
		if not currentHitbox then return end

		local parts = workspace:GetPartsInPart(currentHitbox, overlapParams)
		for _, part in parts do
			local hitCharacter = part:FindFirstAncestorOfClass("Model")
			local hitPlayer = hitCharacter and Players:GetPlayerFromCharacter(hitCharacter)
			processHitPlayer(player, playerState, hitPlayer, hitCharacter)
		end
	end)
	--// Keep compatibility with KnifeService.OnPlayerDied cleanup.
	playerState.currentTickConnection = heartbeatConn

	--// Supplementary detection: .Touched catches physics-contact cases the overlap loop can miss between frames.
	touchedConn = hitbox.Touched:Connect(function(part)
		local hitCharacter = part:FindFirstAncestorOfClass("Model")
		local hitPlayer = hitCharacter and Players:GetPlayerFromCharacter(hitCharacter)
		processHitPlayer(player, playerState, hitPlayer, hitCharacter)
	end)
end

function StabAction.serverCleanup(_player: Player, playerState: any)
	if playerState.currentTickConnection then
		playerState.currentTickConnection:Disconnect()
		playerState.currentTickConnection = nil
	end
	playerState.alreadyHit = {}
end

return StabAction
```

- [ ] **Step 2: Commit**

```bash
git add src/Server/KnifeService/Actions/StabAction.lua
git commit -m "feat(knife): stab uses StabHitWindow with GetPartsInPart primary + Touched supplement"
```

---

### Task 15: `GunController` — generation counter, `pendingAction`, `cancelPending`, idle lifecycle

**Files:**
- Modify: `src/Client/GunController/init.lua`

- [ ] **Step 1: Add imports and state fields**

At the top of `src/Client/GunController/init.lua`, add (if not already present):

```lua
local AnimationsConfigs = require(ReplicatedStorage.Animations.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local AnimationController = require(script.Parent.AnimationController)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
```

Below the existing `safetyTimeoutThread` declaration, add:

```lua
local pendingActionGeneration = 0
local pendingAction: any = nil
local idleHandle: any = nil
```

- [ ] **Step 2: Add `cancelPending` and `restartIdle` helpers**

Below the state fields, above `GunController.onGunEquipped`:

```lua
local function restartIdle()
	if not gunEquipped then return end
	local character = localPlayer.Character
	if not character then return end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then return end
	local profile = AnimationProfile.resolve(tool.Name, SharedConfigs.AnimationProfiles, AnimationType.Idle)
	if not profile or profile.id == "" then return end
	idleHandle = AnimationController.playLooped(character, profile.id)
end

local function cancelPending()
	pendingActionGeneration += 1
	if pendingAction then
		if pendingAction.fallbackTimer then task.cancel(pendingAction.fallbackTimer) end
		if pendingAction.hardTimer then task.cancel(pendingAction.hardTimer) end
		pendingAction = nil
	end
	AnimationController.stopCurrent()
	idleHandle = nil
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
	GunStateMachine.resetAll(stateMachine)
	restartIdle()  --// if still equipped + active round, slot fills with idle again
end
```

- [ ] **Step 3: Wire lifecycle**

Update `GunController.onGunEquipped`:

```lua
function GunController.onGunEquipped()
	gunEquipped = true
	debugPrint(DEBUG, `[GunController] Gun equipped`)

	remoteName = `GunAction_{localPlayer.UserId}`
	if remoteConnection then remoteConnection:Disconnect() end
	remoteConnection = NetworkRouter:Listen(remoteName, function(payload)
		GunController._handleServerResponse(payload)
	end)

	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	if tool then
		local toolProfile = SharedConfigs.AnimationProfiles[tool.Name]
		if toolProfile then
			AnimationController.preloadProfile(character, toolProfile)
		end
	end
	restartIdle()
end
```

Update `GunController.onGunUnequipped`:

```lua
function GunController.onGunUnequipped()
	gunEquipped = false
	cancelPending()
	AnimationController.stopCurrent()  --// cancelPending already called restartIdle which no-ops when !gunEquipped
	debugPrint(DEBUG, `[GunController] Gun unequipped`)
end
```

Update `GunController.onPlayerDied`:

```lua
function GunController.onPlayerDied()
	gunEquipped = false
	cancelPending()
end
```

In `_handleServerResponse`, inside the `StateOverride` branch, before the `stateMachine.isShooting = ...` line, insert `cancelPending()`. Also add the `isReloading` sync line:

```lua
cancelPending()
stateMachine.isShooting = payload.overriddenState.isShooting == true
stateMachine.isReloading = payload.overriddenState.isReloading == true
```

Below the `GunController = {}` declaration, add the round-state listener:

```lua
ClientEventBus:Connect("RoundStateChanged", function(newState: string)
	if newState ~= RoundConfigs.GAME_STATES.RoundActive then
		cancelPending()
	end
end)
```

- [ ] **Step 4: Commit**

```bash
git add src/Client/GunController/init.lua
git commit -m "feat(gun): cancelPending scaffold, idle lifecycle, round-state listener"
```

---

### Task 16: `GunController.performAction` — windup/release with shoot chain support

**Files:**
- Modify: `src/Client/GunController/init.lua`

- [ ] **Step 1: Add `schedulePendingRelease` helper**

Above `GunController.performAction`, add (mirrors KnifeController's helper):

```lua
local function schedulePendingRelease(profile: any, onRelease: (snapshot: any) -> ())
	local handle = pendingAction and pendingAction.handle
	if not handle then return end
	local capturedGen = pendingActionGeneration

	local releaseTime = (profile and profile.releaseTime) or AnimationsConfigs.DefaultReleaseTime
	local hardTimeout = releaseTime + AnimationsConfigs.ReleaseTimeoutBuffer
	local fired = false

	local function fireOnce(source: string)
		if fired then return end
		if capturedGen ~= pendingActionGeneration then return end
		local snapshot = pendingAction
		if not snapshot then return end
		fired = true
		if snapshot.fallbackTimer then task.cancel(snapshot.fallbackTimer) end
		if snapshot.hardTimer then task.cancel(snapshot.hardTimer) end
		onRelease(snapshot)
	end

	task.spawn(function()
		local markerFired = handle.waitForMarker(AnimationsConfigs.MarkerNames.Release)
		if markerFired then fireOnce("marker") end
	end)

	pendingAction.fallbackTimer = task.delay(releaseTime, function()
		fireOnce("fallback")
	end)

	pendingAction.hardTimer = task.delay(hardTimeout, function()
		if not fired then fireOnce("hardtimeout") end
	end)
end
```

- [ ] **Step 2: Rewrite `GunController.performAction`**

Replace the existing `performAction` with:

```lua
function GunController.performAction(actionName: string)
	if not gunEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = GunStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		debugPrint(DEBUG, `[GunController] Action blocked: {actionName}`)
		return
	end

	sequenceId += 1
	pendingActionGeneration += 1
	local thisGen = pendingActionGeneration
	local thisSeq = sequenceId

	local character = localPlayer.Character
	if not character then
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	local tool = character:FindFirstChildWhichIsA("Tool")
	local handlePart = tool and tool:FindFirstChild("Handle") :: BasePart?
	local shootPoint = handlePart and handlePart:FindFirstChild("ShootPoint")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not hrp or not tool then
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	--// Capture rest offset against the ShootPoint for shoots, or Handle for reload.
	local referencePart: BasePart? = nil
	if actionName == "Shoot" and shootPoint then
		--// ShootPoint is an Attachment — use its WorldCFrame.
		local worldCFrame = shootPoint.WorldCFrame
		local restOffset = hrp.CFrame:ToObjectSpace(worldCFrame)
		referencePart = handlePart  --// only used to satisfy type-checker; restOffset is the real data
		pendingAction = {
			generation = thisGen,
			sequenceId = thisSeq,
			actionName = actionName,
			restOffset = restOffset,
			handle = nil,
		}
	elseif actionName == "Reload" then
		pendingAction = {
			generation = thisGen,
			sequenceId = thisSeq,
			actionName = actionName,
			restOffset = nil,
			handle = nil,
		}
	else
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	--// Stop idle so the action's animation owns the slot.
	if idleHandle then idleHandle = nil end

	local profiles = SharedConfigs.AnimationProfiles
	if actionName == "Shoot" then
		local leadIn = AnimationProfile.resolve(tool.Name, profiles, AnimationType.ShootLeadIn)
		local shoot = AnimationProfile.resolve(tool.Name, profiles, AnimationType.Shoot)
		if not shoot or shoot.id == "" then
			warn(`[GunController] Shoot animation missing for {tool.Name} — aborting action`)
			GunStateMachine.resetAction(stateMachine, actionName)
			pendingAction = nil
			restartIdle()
			return
		end
		local ids: { string } = {}
		if leadIn and leadIn.id ~= "" then table.insert(ids, leadIn.id) end
		table.insert(ids, shoot.id)
		pendingAction.handle = AnimationController.playChain(character, ids)

		schedulePendingRelease(shoot, function(snapshot)
			if snapshot.generation ~= pendingActionGeneration then return end
			local currentChar = localPlayer.Character
			local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not currentHrp then return end

			local restOriginCFrame = currentHrp.CFrame * snapshot.restOffset
			local restOrigin = restOriginCFrame.Position
			local aim = InputPosition.getInputPosition()
			if not aim then return end
			local delta = aim - restOrigin
			if delta.Magnitude < 0.01 then return end
			local direction = delta.Unit

			action.clientExecute(stateMachine, direction)

			NetworkRouter:Call(remoteName, {
				desiredAction = actionName,
				directionVector = direction,
				restOrigin = restOrigin,
				sequenceId = snapshot.sequenceId,
			})
		end)
	elseif actionName == "Reload" then
		local reload = AnimationProfile.resolve(tool.Name, profiles, AnimationType.Reload)
		if reload and reload.id ~= "" then
			pendingAction.handle = AnimationController.play(character, reload.id)
		end
		action.clientExecute(stateMachine, nil)
		NetworkRouter:Call(remoteName, {
			desiredAction = actionName,
			sequenceId = thisSeq,
		})
	end

	if safetyTimeoutThread then task.cancel(safetyTimeoutThread) end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSeq then
			GunStateMachine.resetAction(stateMachine, actionName)
			pendingAction = nil
			restartIdle()
		end
	end)
end
```

- [ ] **Step 3: Update `_handleServerResponse` CooldownReset branch to restart idle**

Inside `_handleServerResponse`, in the `CooldownReset` branch after the `GunStateMachine.resetAction(...)` line, add:

```lua
pendingAction = nil
restartIdle()
```

- [ ] **Step 4: Commit**

```bash
git add src/Client/GunController/init.lua
git commit -m "feat(gun): windup/release with LeadIn+Shoot chain and reload dispatch"
```

---

### Task 17: Gun `ShootAction` client refactor — slim to release-fired client execute

**Files:**
- Modify: `src/Client/GunController/Actions/ShootAction.lua`

- [ ] **Step 1: Rewrite `ShootAction.lua` (client)**

File `src/Client/GunController/Actions/ShootAction.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration

do
	local profile = AnimationProfile.resolve("SmallPistol", SharedConfigs.AnimationProfiles, AnimationType.Shoot)
	ShootAction.animationId = (profile and profile.id) or ""
end

--// Invoked from the release callback in GunController. Animation is already playing via the chain.
function ShootAction.clientExecute(_state, _directionVector)
	SFXController.playUI(SharedConfigs.ShootSoundId)
end

return ShootAction
```

- [ ] **Step 2: Commit**

```bash
git add src/Client/GunController/Actions/ShootAction.lua
git commit -m "feat(gun): slim ShootAction client to release-fired sfx"
```

---

### Task 18: Gun server — `ShootAction` consumes `restOrigin`

**Files:**
- Modify: `src/Server/GunService/Actions/ShootAction.lua`
- Modify: `src/Server/GunService/init.lua`

- [ ] **Step 1: Pass `restOrigin` through `GunService`**

In `src/Server/GunService/init.lua`, inside `_handleActionRequest`, at the `action.serverExecute(...)` call site, update to:

```lua
action.serverExecute(player, state, directionVector, payload.restOrigin)
```

- [ ] **Step 2: Rewrite `ShootAction.serverExecute`**

File `src/Server/GunService/Actions/ShootAction.lua` — rewrite the function:

```lua
local AnimationsConfigs = require(game:GetService("ReplicatedStorage").Animations.Configs)

function ShootAction.serverExecute(
	player: Player,
	_playerState: any,
	directionVector: Vector3?,
	restOrigin: Vector3?
)
	if not directionVector then
		warn(`[ShootAction] missing directionVector for {player.Name}`)
		return
	end
	if not restOrigin then
		warn(`[ShootAction] missing restOrigin for {player.Name}`)
		return
	end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	if (restOrigin - rootPart.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance then
		warn(`[ShootAction] restOrigin out of range for {player.Name}`)
		return
	end

	local direction = directionVector.Unit
	local origin = restOrigin

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction * SharedConfigs.MaxRange, raycastParams)
	local hitPos = result and result.Position or (origin + direction * SharedConfigs.MaxRange)

	drawTracer(origin, hitPos)

	if result then
		local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")
		if hitCharacter then
			local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			if hitPlayer and hitPlayer ~= player
				and TeleportMetadataService.GetTeam(hitPlayer) ~= TeleportMetadataService.GetTeam(player)
			then
				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:SetAttribute("LastDamageSource", player.UserId)
					humanoid:TakeDamage(SharedConfigs.ShootDamage)
				end

				debugPrint(DEBUG, `[ShootAction] {player.Name} shot {hitPlayer.Name}`)

				local remoteName = `GunAction_{player.UserId}`
				NetworkRouter:Call(remoteName, player, {
					payloadType = "ProjectileHitConfirm",
					actionName = "Shoot",
				})
			end
		end
	end
end
```

- [ ] **Step 3: Commit**

```bash
git add src/Server/GunService/init.lua src/Server/GunService/Actions/ShootAction.lua
git commit -m "feat(gun): server Shoot consumes restOrigin"
```

---

### Task 19: Reload action — new client + server modules + registry wiring

**Files:**
- Create: `src/Client/GunController/Actions/ReloadAction.lua`
- Create: `src/Server/GunService/Actions/ReloadAction.lua`
- Modify: `src/Client/GunController/ActionRegistry.lua`
- Modify: `src/Server/GunService/ActionRegistry.lua`
- Modify: `src/Shared/Gun/Configs.lua` (already done in Task 5; verify only)

- [ ] **Step 1: Create client `ReloadAction`**

File `src/Client/GunController/Actions/ReloadAction.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ReloadCooldown
ReloadAction.duration = SharedConfigs.ReloadCooldown

do
	local profile = AnimationProfile.resolve("SmallPistol", SharedConfigs.AnimationProfiles, AnimationType.Reload)
	ReloadAction.animationId = (profile and profile.id) or ""
end

--// Cosmetic-only. GunController.performAction plays the animation before calling this;
--// this function is a no-op beyond any future sfx hook.
function ReloadAction.clientExecute(_state, _directionVector)
end

return ReloadAction
```

- [ ] **Step 2: Create server `ReloadAction`**

File `src/Server/GunService/Actions/ReloadAction.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ReloadCooldown
ReloadAction.duration = SharedConfigs.ReloadCooldown
ReloadAction.animationId = ""

--// No authoritative logic — reload is purely cosmetic. The existing task.delay(cooldown)
--// path in GunService sends CooldownReset back to the client.
function ReloadAction.serverExecute(_player: Player, _playerState: any, _directionVector: Vector3?, _restOrigin: Vector3?)
end

function ReloadAction.serverCleanup(_player: Player, _playerState: any)
end

return ReloadAction
```

- [ ] **Step 3: Register Reload in both registries**

File `src/Client/GunController/ActionRegistry.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local ShootAction = require(script.Parent.Actions.ShootAction)
local ReloadAction = require(script.Parent.Actions.ReloadAction)

return createRegistry({ ShootAction, ReloadAction })
```

File `src/Server/GunService/ActionRegistry.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local ShootAction = require(script.Parent.Actions.ShootAction)
local ReloadAction = require(script.Parent.Actions.ReloadAction)

return createRegistry({ ShootAction, ReloadAction })
```

- [ ] **Step 4: Verify both registries resolve Reload**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local ClientReg = require(game.StarterPlayer.StarterPlayerScripts.GunController.ActionRegistry)
local ServerReg = require(game.ServerScriptService.GunService.ActionRegistry)
print("client reload:", ClientReg.getAction("Reload") ~= nil)
print("server reload:", ServerReg.getAction("Reload") ~= nil)
```

Expected: both `true`.

- [ ] **Step 5: Commit**

```bash
git add src/Client/GunController/Actions/ReloadAction.lua src/Server/GunService/Actions/ReloadAction.lua src/Client/GunController/ActionRegistry.lua src/Server/GunService/ActionRegistry.lua
git commit -m "feat(gun): add cosmetic Reload action (client + server)"
```

---

### Task 20: Bind `R` key to Reload in `InputRouter.Configs`

**Files:**
- Modify: `src/Client/InputRouter/Configs.lua`

- [ ] **Step 1: Add the Reload binding**

File `src/Client/InputRouter/Configs.lua`:

```lua
return {
	DEBUG_MODE = false,

	KnifeBindings = {
		Stab = {
			actionName = "KnifeStab",
			keyboard = Enum.KeyCode.Q,
			gamepad = Enum.KeyCode.ButtonL1,
			touchButton = true,
		},
		Throw = {
			actionName = "KnifeThrow",
			keyboard = Enum.KeyCode.E,
			gamepad = Enum.KeyCode.ButtonR1,
			touchButton = true,
		},
	},

	GunBindings = {
		Shoot = {
			actionName = "GunShoot",
			mouseButton = Enum.UserInputType.MouseButton1,
			gamepad = Enum.KeyCode.ButtonR2,
			touchButton = true,
		},
		Reload = {
			actionName = "GunReload",
			keyboard = Enum.KeyCode.R,
			gamepad = Enum.KeyCode.ButtonX,
			touchButton = true,
		},
	},
}
```

- [ ] **Step 2: Verify `InputRouter` picks up the new action**

Run via `mcp__robloxstudio__execute_luau` in Studio after rejoining:

```lua
local ContextActionService = game:GetService("ContextActionService")
--// After equipping a gun, this action should exist:
print("GunReload bound:", ContextActionService:GetAllBoundActionInfo().GunReload ~= nil)
```

Expected: `true` when a gun is equipped.

- [ ] **Step 3: Commit**

```bash
git add src/Client/InputRouter/Configs.lua
git commit -m "feat(gun): bind R key to Reload via InputRouter"
```

---

### Task 21: Knife server `OnPlayerDied` — extend cleanup

**Files:**
- Modify: `src/Server/KnifeService/init.lua`

Currently `OnPlayerDied` disconnects `currentTickConnection` but does not null out the `.Touched` supplement's connection (which lives on the hitbox and is GC'd with the tool). Verify and add explicit teardown if needed.

- [ ] **Step 1: Review `OnPlayerDied`**

Re-read `src/Server/KnifeService/init.lua` lines around `function KnifeService.OnPlayerDied`. The existing code:

```lua
if state.currentTickConnection then
	state.currentTickConnection:Disconnect()
	state.currentTickConnection = nil
end
state.alreadyHit = {}
```

This already covers the heartbeat. The `.Touched` connection is a local variable inside `StabAction.serverExecute` — it's GC'd when the heartbeat's `tearDown()` runs. But if the player dies *during* the stab window, `currentTickConnection:Disconnect()` fires here but the Touched connection is never disconnected.

- [ ] **Step 2: Store Touched connection on player state for cleanup**

In `src/Server/KnifeService/Actions/StabAction.lua` (from Task 14), replace the local `touchedConn` with a `playerState.stabTouchedConn` assignment:

Change:
```lua
local touchedConn: RBXScriptConnection? = nil
...
touchedConn = hitbox.Touched:Connect(function(part)
```

to:

```lua
--// Stored on playerState so OnPlayerDied can disconnect it if the stab window is active.
playerState.stabTouchedConn = hitbox.Touched:Connect(function(part)
```

And in `tearDown()`:

```lua
local function tearDown()
	if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
	if playerState.stabTouchedConn then
		playerState.stabTouchedConn:Disconnect()
		playerState.stabTouchedConn = nil
	end
	playerState.alreadyHit = {}
	playerState.currentTickConnection = nil
end
```

- [ ] **Step 3: Disconnect in `KnifeService.OnPlayerDied`**

In `src/Server/KnifeService/init.lua`, inside `OnPlayerDied`, after the existing `currentTickConnection` cleanup, add:

```lua
if state.stabTouchedConn then
	state.stabTouchedConn:Disconnect()
	state.stabTouchedConn = nil
end
```

- [ ] **Step 4: Update Types to reflect the new field**

In `src/Server/KnifeService/Types.lua`, find the `PlayerKnifeState` type and add `stabTouchedConn: RBXScriptConnection?` — if the type doesn't exist in strict form, this is a no-op.

- [ ] **Step 5: Commit**

```bash
git add src/Server/KnifeService/init.lua src/Server/KnifeService/Actions/StabAction.lua src/Server/KnifeService/Types.lua
git commit -m "fix(knife): disconnect stab .Touched supplement on player death"
```

---

### Task 22: Manual Studio verification (no code changes)

**Files:** none

This task is verification-only. No commit. Run each check below in Studio (edit environment, with a character rig) and record pass/fail.

- [ ] **Step 1: Equip knife, throw, confirm windup + cosmetic + damage**

Expected sequence:
1. Press E (throw key). Throw animation starts.
2. After ~0.2s the cosmetic knife visually leaves the hand and flies toward cursor.
3. Server raycast spawns an invisible projectile along the rest-origin direction; if it hits a target, damage is applied.
4. Knife returns to empty hand; cooldown lockout until 5s.

- [ ] **Step 2: Equip knife, stab, confirm 1s hit window**

Expected:
1. Press Q (stab). Stab animation plays (currently blank — nothing visual, this is fine).
2. Any enemy player within hitbox reach during the next 1.0s is killed (Health → 0).
3. Touching an ally or self has no effect.

- [ ] **Step 3: Equip gun, shoot, confirm lead-in + release**

Expected:
1. Gun equipped. Idle animation (pistol hold pose) loops.
2. Click. `ShootLeadIn` plays, then `Shoot` plays.
3. At the `Release` marker (or 0.12s into Shoot if no marker), raycast fires and draws a tracer toward target.
4. After shoot animation ends, idle resumes.

- [ ] **Step 4: Press R, confirm reload animation + state machine lockout**

Expected:
1. Press R. Reload animation plays. Idle stops.
2. Clicking during reload does not fire (state machine rejects).
3. After reload cooldown (5s floor or animation length, whichever is longer), idle resumes and shoot becomes available.

- [ ] **Step 5: Cancel mid-throw by unequipping**

Expected:
1. Press E. Throw animation starts.
2. Within the windup (before 0.2s), unequip the knife via tool-swap.
3. Throw animation stops; no cosmetic projectile spawns; no remote is sent; state machine resets.

- [ ] **Step 6: Confirm singleton enforcement**

In the command bar while playing:

```lua
local AnimationController = require(game.StarterPlayer.StarterPlayerScripts.AnimationController)
local char = game.Players.LocalPlayer.Character
local h1 = AnimationController.play(char, "rbxassetid://100789163917300")
task.wait(0.1)
local h2 = AnimationController.play(char, "rbxassetid://86262836320062")
task.wait(0.1)
print("h1 track playing:", h1.track and h1.track.IsPlaying)  --// expected false
print("h2 track playing:", h2.track and h2.track.IsPlaying)  --// expected true
```

- [ ] **Step 7: Record findings and file issues if any step fails**

No commit. If anything fails, open a new task / issue describing which step and the observed behavior.

---

## Final Notes

- **Commit graph:** 20 commits (Tasks 1-21; Task 22 is verification-only). Each is self-contained and reviewable.
- **Rollback points:** every task leaves the codebase in a working (possibly visually-less-polished) state. Tasks 6-8 (state/validator changes) are the hardest to roll back individually because Tasks 11-20 depend on their shapes.
- **Post-merge manual step:** Small Pistol animation IDs are hardcoded. When new gun variants arrive, add their profile to `Shared/Gun/Configs.lua:AnimationProfiles` keyed by the exact `Tool.Name`; no code changes needed elsewhere.
- **Animator marker authoring:** the animator should drop a marker named `"Release"` (configurable via `Animations/Configs.MarkerNames.Release`) inside the Throw animation at the release frame and inside the Shoot animation at the fire frame. If absent, the numeric `releaseTime` in each profile is used as the fallback.
