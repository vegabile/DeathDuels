# Powers System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the server-authoritative powers system described in `docs/superpowers/specs/2026-04-16-powers-system-design.md`. Plumbing only — no concrete Powers ship.

**Architecture:** One `PowerService` instance per player, OOP on a class table with colon-method invocation. `:Activate(powerName, payload)` runs 7 gates in a fixed order and hands off to the resolved `Power:Execute` on success. Lock == cooldown; no execution-lifecycle tracking. Loadout is passed into `PowerService.new` by the executor (spec section 4 clarification — see Task 3 notes).

**Tech Stack:** Luau, Roblox services (`Players`, `ReplicatedStorage`, `ServerScriptService`), existing `NetworkRouter` / `ServerEventBus` / `ActionRegistryFactory` modules. Tests run via `mcp__robloxstudio__execute_luau` in the edit environment (never playtest).

---

## File Structure

Created in this plan:

- `src/Shared/Power/PowerFailReason.lua` — frozen enum table
- `src/Shared/Power/Types.lua` — exported types
- `src/Shared/Power/PayloadValidator.lua` — envelope validator
- `src/Server/PowerService/Configs.lua` — `DEBOUNCE`, `DEBUG_MODE`
- `src/Server/PowerService/Types.lua` — internal instance shape
- `src/Server/PowerService/PowerRegistry.lua` — thin `.getPower` wrapper over `ActionRegistryFactory`
- `src/Server/PowerService/init.lua` — class, map, `.new` / `.Get` / `:Destroy` / `:Activate` + round-state listener + `_reset` test hook
- `src/Server/PowerService/executor.server.lua` — `PlayerAdded` / `PlayerRemoving` wiring + remote handler
- `src/Server/PowerService/integration_power_system.test.lua` — 14 integration cases
- `src/Server/PowerService/Powers/` — empty folder (future powers land here)

No existing files are modified.

---

### Task 1: Shared layer (enum, types, validator)

**Files:**
- Create: `src/Shared/Power/PowerFailReason.lua`
- Create: `src/Shared/Power/Types.lua`
- Create: `src/Shared/Power/PayloadValidator.lua`

- [ ] **Step 1: Create the frozen enum**

File `src/Shared/Power/PowerFailReason.lua`:

```lua
--// Single source of truth for every failure reason produced by PowerService.
--// `Locked` is reserved — unused in v1 (lock == cooldown).
return table.freeze({
	UnknownPower  = "UnknownPower",
	OnCooldown    = "OnCooldown",
	Debounced     = "Debounced",
	Locked        = "Locked",
	InvalidState  = "InvalidState",
	InvalidTarget = "InvalidTarget",
	NoPermission  = "NoPermission",
})
```

- [ ] **Step 2: Create the shared type module**

File `src/Shared/Power/Types.lua`:

```lua
export type PowerFailReason = "UnknownPower" | "OnCooldown" | "Debounced"
	| "Locked" | "InvalidState" | "InvalidTarget" | "NoPermission"

export type PowerResult = { success: boolean, reason: PowerFailReason? }

export type Power = {
	name: string,
	cooldown: number,
	validatePayload: (payload: any) -> (boolean, PowerFailReason?),
	Execute: (self: Power, player: Player, payload: any) -> (),
}

export type ActivateRequest  = { powerName: string, payload: any, sequenceId: number }
export type ActivateResponse = { sequenceId: number, result: PowerResult }

export type Loadout = { Power: string? }

return {}
```

- [ ] **Step 3: Create the payload validator**

File `src/Shared/Power/PayloadValidator.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local PayloadValidator = {}

--// Best-effort sequenceId extraction — always returns a number ≥ 0, even on failure.
local function sanitizeSequenceId(raw: any): number
	if type(raw) == "number" and raw >= 0 then return raw end
	return 0
end

--// Returns (ok, reason?, sequenceId).
--// sequenceId is always returned so the handler can echo on rejection.
function PayloadValidator.validate(envelope: any): (boolean, string?, number)
	if type(envelope) ~= "table" then
		return false, Reasons.InvalidTarget, 0
	end

	local sequenceId = sanitizeSequenceId(envelope.sequenceId)

	if type(envelope.powerName) ~= "string" or envelope.powerName == "" then
		return false, Reasons.UnknownPower, sequenceId
	end

	if type(envelope.sequenceId) ~= "number" or envelope.sequenceId < 0 then
		return false, Reasons.InvalidTarget, sequenceId
	end

	--// payload is intentionally `any` — per-power validation happens later in Power.validatePayload.
	return true, nil, sequenceId
end

return PayloadValidator
```

- [ ] **Step 4: Smoke-test the shared layer via execute_luau**

Run this snippet via `mcp__robloxstudio__execute_luau` (after argon sync picks up the new files):

```lua
local RS = game:GetService("ReplicatedStorage")
local Reasons = require(RS.Power.PowerFailReason)
local PV = require(RS.Power.PayloadValidator)

local passed, failed = 0, 0
local function check(label, cond) if cond then passed += 1; print("PASS: " .. label) else failed += 1; print("FAIL: " .. label) end end

--// Enum is frozen
check("enum frozen", not pcall(function() Reasons.UnknownPower = "mutated" end))
check("enum has all 7 keys", Reasons.UnknownPower and Reasons.OnCooldown and Reasons.Debounced
	and Reasons.Locked and Reasons.InvalidState and Reasons.InvalidTarget and Reasons.NoPermission)

--// Validator happy path
local ok, reason, seq = PV.validate({ powerName = "dash", sequenceId = 3, payload = {} })
check("validator ok", ok and reason == nil and seq == 3)

--// Validator non-table
ok, reason, seq = PV.validate("nope")
check("validator rejects non-table", not ok and reason == Reasons.InvalidTarget and seq == 0)

--// Validator bad powerName
ok, reason, seq = PV.validate({ powerName = 42, sequenceId = 5 })
check("validator rejects non-string powerName", not ok and reason == Reasons.UnknownPower and seq == 5)

--// Validator negative sequenceId sanitized
ok, reason, seq = PV.validate({ powerName = "dash", sequenceId = -1 })
check("validator sanitizes negative seq", not ok and reason == Reasons.InvalidTarget and seq == 0)

print(string.format("\n%d passed, %d failed", passed, failed))
```

Expected output: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add src/Shared/Power/PowerFailReason.lua src/Shared/Power/Types.lua src/Shared/Power/PayloadValidator.lua
git commit -m "feat(powers): shared enum, types, and envelope validator"
```

---

### Task 2: Server scaffolding — Configs, Types, PowerRegistry

**Files:**
- Create: `src/Server/PowerService/Configs.lua`
- Create: `src/Server/PowerService/Types.lua`
- Create: `src/Server/PowerService/PowerRegistry.lua`
- Create: `src/Server/PowerService/Powers/` (empty folder — create a `.keep` or empty file so Argon tracks it)

- [ ] **Step 1: Create the server Configs module**

File `src/Server/PowerService/Configs.lua`:

```lua
return {
	DEBOUNCE   = 0.05,   --// seconds; per-player per-power spam guard
	DEBUG_MODE = false,
}
```

- [ ] **Step 2: Create the server Types module**

File `src/Server/PowerService/Types.lua`:

```lua
local SharedTypes = require(game:GetService("ReplicatedStorage").Power.Types)

export type Power = SharedTypes.Power
export type PowerResult = SharedTypes.PowerResult
export type Loadout = SharedTypes.Loadout

export type PowerService = {
	player: Player,
	_equippedPower: Power?,
	_cooldowns: { [string]: number },
	_lastAttempt: { [string]: number },
	_registry: { getPower: (name: string) -> Power? },
}

return {}
```

- [ ] **Step 3: Create PowerRegistry**

File `src/Server/PowerService/PowerRegistry.lua`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

--// Powers/ is empty in v1; follow-up features add entries here as { Power1, Power2, ... }.
local base = createRegistry({})

local PowerRegistry = {}

function PowerRegistry.getPower(name: string)
	return base.getAction(name)
end

return PowerRegistry
```

- [ ] **Step 4: Create the empty Powers folder**

Create an empty placeholder file so Argon tracks the folder. File `src/Server/PowerService/Powers/.keep`:

```
```

(Empty file. Can be deleted once the first real Power module is added in a future feature.)

- [ ] **Step 5: Smoke-test via execute_luau**

Run this snippet via `mcp__robloxstudio__execute_luau`:

```lua
local SSS = game:GetService("ServerScriptService")
local Configs = require(SSS.PowerService.Configs)
local Registry = require(SSS.PowerService.PowerRegistry)

print("DEBOUNCE:", Configs.DEBOUNCE)
print("getPower('nothing'):", Registry.getPower("nothing"))
assert(Configs.DEBOUNCE == 0.05, "DEBOUNCE should be 0.05")
assert(Registry.getPower("nothing") == nil, "Empty registry should return nil")
print("server scaffolding OK")
```

Expected: `DEBOUNCE:	0.05`, a warn from ActionRegistryFactory about "No action found for: nothing", `getPower('nothing'):	nil`, `server scaffolding OK`.

- [ ] **Step 6: Commit**

```bash
git add src/Server/PowerService/Configs.lua src/Server/PowerService/Types.lua src/Server/PowerService/PowerRegistry.lua src/Server/PowerService/Powers/.keep
git commit -m "feat(powers): server configs, types, and registry wrapper"
```

---

### Task 3: PowerService class (`init.lua`)

This is the core module. All 7 activation gates live here.

**Spec clarification — loadout injection:** The spec's section 4 step 1 says `PowerService.new` reads `TeleportMetadataService.GetLoadout` directly. This plan moves that read into `executor.server.lua` and has `.new` accept the loadout as a parameter. Reason: honors spec section 11's "Depend on contracts, not implementations" constraint and makes the integration test possible without a reset hook on `TeleportMetadataService`. Production behavior is identical — executor reads the metadata and hands the result to `.new`.

**Files:**
- Create: `src/Server/PowerService/init.lua`

- [ ] **Step 1: Write the init.lua file in full**

File `src/Server/PowerService/init.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local Configs = require(script.Configs)
local PowerRegistry = require(script.PowerRegistry)
local ServerTypes = require(script.Types)

type Power = ServerTypes.Power
type PowerResult = ServerTypes.PowerResult
type Loadout = ServerTypes.Loadout

--// ─── Module state ────────────────────────────────────────────────────────

local instancesByPlayer: { [Player]: any } = {}
local currentRoundState: string = ""

ServerEventBus:Connect("RoundStateChanged", function(newState: string)
	currentRoundState = newState
end)

--// ─── Class ───────────────────────────────────────────────────────────────

local PowerService = {}
PowerService.__index = PowerService

function PowerService.new(player: Player, loadout: Loadout?, registry: any?): any
	local self = setmetatable({}, PowerService)
	self.player = player
	self._cooldowns = {}
	self._lastAttempt = {}
	self._registry = registry or PowerRegistry
	self._equippedPower = nil

	if loadout == nil or type(loadout.Power) ~= "string" then
		warn(`[POWER] Missing loadout.Power for {player.Name}`)
	else
		local resolved = self._registry.getPower(loadout.Power:lower())
		if resolved then
			self._equippedPower = resolved
		else
			warn(`[POWER] Unresolved power '{loadout.Power}' for {player.Name}`)
		end
	end

	instancesByPlayer[player] = self
	return self
end

function PowerService.Get(player: Player): any?
	return instancesByPlayer[player]
end

function PowerService:Destroy()
	table.clear(self._cooldowns)
	table.clear(self._lastAttempt)
	instancesByPlayer[self.player] = nil
end

function PowerService:Activate(powerName: string, payload: any): PowerResult
	local now = tick()

	--// 1. Resolve requested power
	if type(powerName) ~= "string" then
		return { success = false, reason = Reasons.UnknownPower }
	end
	local requested = self._registry.getPower(powerName:lower())
	if not requested then
		return { success = false, reason = Reasons.UnknownPower }
	end

	--// 2. Permission — requested must equal equipped
	if self._equippedPower == nil or self._equippedPower.name ~= requested.name then
		return { success = false, reason = Reasons.NoPermission }
	end

	--// 3. External state gates
	if not self.player:IsDescendantOf(Players) then
		return { success = false, reason = Reasons.InvalidState }
	end
	if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
		return { success = false, reason = Reasons.InvalidState }
	end
	local char = self.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return { success = false, reason = Reasons.InvalidState }
	end

	--// 4. Debounce — stamp runs on every attempt from here on
	local lastAttempt = self._lastAttempt[requested.name] or 0
	if (now - lastAttempt) < Configs.DEBOUNCE then
		self._lastAttempt[requested.name] = now
		return { success = false, reason = Reasons.Debounced }
	end

	--// 5. Payload validation
	local ok, reason = requested.validatePayload(payload)
	if not ok then
		self._lastAttempt[requested.name] = now
		return { success = false, reason = reason or Reasons.InvalidTarget }
	end

	--// 6. Cooldown check
	local expiry = self._cooldowns[requested.name] or 0
	if now < expiry then
		self._lastAttempt[requested.name] = now
		return { success = false, reason = Reasons.OnCooldown }
	end

	--// 7. Lock == cooldown — start cooldown BEFORE handoff
	self._cooldowns[requested.name] = now + requested.cooldown
	self._lastAttempt[requested.name] = now

	--// 8. Handoff — fire-and-forget, no pcall
	requested:Execute(self.player, payload)

	return { success = true, reason = nil }
end

--// ─── Test hooks ──────────────────────────────────────────────────────────
--// Called only by integration_power_system.test.lua.

function PowerService._reset()
	for _, svc in instancesByPlayer do
		table.clear(svc._cooldowns)
		table.clear(svc._lastAttempt)
	end
	table.clear(instancesByPlayer)
end

return PowerService
```

- [ ] **Step 2: Smoke-test that init.lua loads and the class constructs**

Run via `mcp__robloxstudio__execute_luau`:

```lua
local SSS = game:GetService("ServerScriptService")
local PowerService = require(SSS.PowerService)

PowerService._reset()

local fakePlayer = { Name = "Smoke", UserId = 999 }
local svc = PowerService.new(fakePlayer, nil, { getPower = function() return nil end })
assert(svc ~= nil, "construct returned nil")
assert(PowerService.Get(fakePlayer) == svc, "Get should return the instance")

svc:Destroy()
assert(PowerService.Get(fakePlayer) == nil, "Destroy should clear the map")

print("init.lua smoke OK")
```

Expected: one `warn` about missing loadout, then `init.lua smoke OK`.

- [ ] **Step 3: Commit**

```bash
git add src/Server/PowerService/init.lua
git commit -m "feat(powers): PowerService class with 7-gate Activate flow"
```

---

### Task 4: Integration test — all 14 cases

**Files:**
- Create: `src/Server/PowerService/integration_power_system.test.lua`

- [ ] **Step 1: Write the integration test file**

File `src/Server/PowerService/integration_power_system.test.lua`:

```lua
--// Integration test for the Powers system. Run via mcp__robloxstudio__execute_luau.
--// Uses mock player tables + an injected fake registry — no real players needed.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerService = require(ServerScriptService.PowerService)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local Configs = require(ServerScriptService.PowerService.Configs)

local passed, failed = 0, 0
local function check(label: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
		print(`PASS: {label}`)
	else
		failed += 1
		print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
	end
end

--// ─── Fixtures ────────────────────────────────────────────────────────────

--// Minimal Humanoid-like table the :Activate flow can read.
local function mockCharacter(health: number)
	local hum = { Health = health, ClassName = "Humanoid" }
	local char = {}
	function char:FindFirstChildOfClass(className)
		if className == "Humanoid" then return hum end
		return nil
	end
	return char, hum
end

--// Fake Player supporting every field PowerService reads.
local function mockPlayer(opts)
	opts = opts or {}
	local char, hum
	if opts.hasCharacter ~= false then
		char, hum = mockCharacter(opts.health or 100)
	end
	local player
	player = {
		Name = opts.name or "Tester",
		UserId = opts.userId or 42,
		Character = char,
		IsDescendantOf = function(self, container)
			if opts.inGame == false then return false end
			return container == game:GetService("Players")
		end,
	}
	return player, hum
end

local function makePower(overrides)
	overrides = overrides or {}
	local calls = {}
	local power = {
		name = overrides.name or "testpower",
		cooldown = overrides.cooldown or 1,
		validatePayload = overrides.validatePayload or function(_) return true, nil end,
	}
	function power:Execute(player, payload)
		table.insert(calls, { player = player, payload = payload })
	end
	power._calls = calls
	return power
end

local function makeRegistry(powers)
	local map = {}
	for _, p in powers do map[p.name] = p end
	return {
		getPower = function(name)
			return map[name]
		end
	}
end

local function setRoundActive()  ServerEventBus:Fire("RoundStateChanged", "RoundActive")      end
local function setRoundInactive() ServerEventBus:Fire("RoundStateChanged", "RoundIntermission") end

local function freshSession()
	PowerService._reset()
	setRoundActive()
end

--// ─── Case 1: Unknown power requested ─────────────────────────────────────

do
	freshSession()
	local power = makePower({ name = "testpower" })
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local result = svc:Activate("garbage", {})
	check("1. unknown power → UnknownPower", result.success == false and result.reason == Reasons.UnknownPower)
end

--// ─── Case 2: Equipped mismatch → NoPermission ────────────────────────────

do
	freshSession()
	local a = makePower({ name = "a" })
	local b = makePower({ name = "b" })
	local registry = makeRegistry({ a, b })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "a" }, registry)

	local result = svc:Activate("b", {})
	check("2. equipped mismatch → NoPermission", result.success == false and result.reason == Reasons.NoPermission)
end

--// ─── Case 3: Player left game → InvalidState ─────────────────────────────

do
	freshSession()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer({ inGame = false })
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local result = svc:Activate("testpower", {})
	check("3. player not in game → InvalidState", result.success == false and result.reason == Reasons.InvalidState)
end

--// ─── Case 4: Round not active → InvalidState ─────────────────────────────

do
	freshSession()
	setRoundInactive()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local result = svc:Activate("testpower", {})
	check("4. round inactive → InvalidState", result.success == false and result.reason == Reasons.InvalidState)
end

--// ─── Case 5: Character dead → InvalidState ───────────────────────────────

do
	freshSession()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer({ health = 0 })
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local result = svc:Activate("testpower", {})
	check("5. character dead → InvalidState", result.success == false and result.reason == Reasons.InvalidState)
end

--// ─── Case 6: Debounced ───────────────────────────────────────────────────

do
	freshSession()
	local power = makePower({ cooldown = 10 })   --// long cooldown so it's the debounce, not the cooldown
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local r1 = svc:Activate("testpower", {})
	local r2 = svc:Activate("testpower", {})
	check("6a. first call succeeds", r1.success == true)
	check("6b. second within debounce → Debounced",
		r2.success == false and r2.reason == Reasons.Debounced)
end

--// ─── Case 7: Payload invalid → InvalidTarget ─────────────────────────────

do
	freshSession()
	local power = makePower({
		validatePayload = function(payload)
			if type(payload) ~= "table" or payload.target == nil then
				return false, Reasons.InvalidTarget
			end
			return true, nil
		end,
	})
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local result = svc:Activate("testpower", {})
	check("7. invalid payload → InvalidTarget", result.success == false and result.reason == Reasons.InvalidTarget)
end

--// ─── Case 8: On cooldown ─────────────────────────────────────────────────

do
	freshSession()
	local power = makePower({ cooldown = 0.5 })
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local r1 = svc:Activate("testpower", {})
	task.wait(Configs.DEBOUNCE + 0.02)   --// clear debounce window
	local r2 = svc:Activate("testpower", {})
	check("8a. first call succeeds", r1.success == true)
	check("8b. second post-debounce within cooldown → OnCooldown",
		r2.success == false and r2.reason == Reasons.OnCooldown)
end

--// ─── Case 9: Happy path ──────────────────────────────────────────────────

do
	freshSession()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)
	local payload = { foo = "bar" }

	local result = svc:Activate("testpower", payload)
	check("9a. happy path success=true", result.success == true)
	check("9b. happy path reason=nil", result.reason == nil)
	check("9c. Execute called exactly once", #power._calls == 1)
	check("9d. Execute called with player", power._calls[1] and power._calls[1].player == player)
	check("9e. Execute called with payload", power._calls[1] and power._calls[1].payload == payload)
end

--// ─── Case 10: Cooldown release after wait ────────────────────────────────

do
	freshSession()
	local power = makePower({ cooldown = 0.3 })
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)

	local r1 = svc:Activate("testpower", {})
	task.wait(0.35)   --// past both debounce and cooldown
	local r2 = svc:Activate("testpower", {})
	check("10a. first call succeeds", r1.success == true)
	check("10b. second call after cooldown succeeds", r2.success == true)
end

--// ─── Case 11: Destroy clears map ─────────────────────────────────────────

do
	freshSession()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "testpower" }, registry)
	check("11a. Get returns instance pre-destroy", PowerService.Get(player) == svc)
	svc:Destroy()
	check("11b. Get returns nil post-destroy", PowerService.Get(player) == nil)
end

--// ─── Case 12: Loadout missing .Power → NoPermission ──────────────────────

do
	freshSession()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, nil, registry)   --// no loadout at all

	local result = svc:Activate("testpower", {})
	check("12. missing loadout → NoPermission", result.success == false and result.reason == Reasons.NoPermission)
end

--// ─── Case 13: Loadout .Power unresolved → NoPermission ───────────────────

do
	freshSession()
	local power = makePower()
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "nonsense" }, registry)

	local result = svc:Activate("testpower", {})
	check("13. unresolved .Power → NoPermission", result.success == false and result.reason == Reasons.NoPermission)
end

--// ─── Case 14: .Power case-insensitive resolve ────────────────────────────

do
	freshSession()
	local power = makePower({ name = "dash" })
	local registry = makeRegistry({ power })
	local player = mockPlayer()
	local svc = PowerService.new(player, { Power = "DaSh" }, registry)

	local result = svc:Activate("dash", {})
	check("14. mixed-case .Power resolves", result.success == true)
end

print(`\n{passed} passed, {failed} failed`)
```

- [ ] **Step 2: Run the integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game:GetService("ServerScriptService").PowerService.integration_power_system)
```

Expected output ends with: `22 passed, 0 failed` (several cases have multiple checks — exactly 22 total).

If any case fails, fix the implementation before proceeding. Do not move to Task 5 until this run is clean.

- [ ] **Step 3: Commit**

```bash
git add src/Server/PowerService/integration_power_system.test.lua
git commit -m "test(powers): integration suite covering all 14 spec cases"
```

---

### Task 5: Executor — remote wiring + player lifecycle

**Files:**
- Create: `src/Server/PowerService/executor.server.lua`

- [ ] **Step 1: Write the executor**

File `src/Server/PowerService/executor.server.lua`:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local PayloadValidator = require(ReplicatedStorage.Power.PayloadValidator)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local PowerService = require(script.Parent)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local function remoteName(player: Player): string
	return `PowerAction_{player.UserId}`
end

local function fireResponse(player: Player, sequenceId: number, result: { success: boolean, reason: string? })
	NetworkRouter:Call(remoteName(player), player, {
		sequenceId = sequenceId,
		result     = result,
	})
end

local function setupPlayer(player: Player)
	local name = remoteName(player)
	NetworkRouter:CreateRemoteEvent(name)

	local loadout = TeleportMetadataService.GetLoadout(player.UserId)
	PowerService.new(player, loadout)

	NetworkRouter:Listen(name, function(firingPlayer, envelope)
		if firingPlayer ~= player then
			warn(`[POWER] Remote spoofing: {firingPlayer.Name} on {player.Name}'s remote`)
			return
		end

		local ok, reason, sequenceId = PayloadValidator.validate(envelope)
		if not ok then
			warn(`[POWER] Malformed envelope from {player.Name}: {reason}`)
			fireResponse(player, sequenceId, { success = false, reason = reason })
			return
		end

		local svc = PowerService.Get(player)
		if not svc then
			warn(`[POWER] No PowerService instance for {player.Name}`)
			fireResponse(player, sequenceId, { success = false, reason = Reasons.InvalidState })
			return
		end

		local result = svc:Activate(envelope.powerName, envelope.payload)
		fireResponse(player, sequenceId, result)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	local svc = PowerService.Get(player)
	if svc then svc:Destroy() end
	NetworkRouter:Remove(remoteName(player))
end)
```

- [ ] **Step 2: Smoke-test the executor loads without errors**

Run via `mcp__robloxstudio__execute_luau`:

```lua
--// The executor is a *.server.lua script — it runs on its own at server start.
--// Here we just verify the modules it requires load cleanly and the remote
--// creation helper works with an existing test player (if any).

local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")

local PowerService = require(SSS.PowerService)

for _, player in Players:GetPlayers() do
	local svc = PowerService.Get(player)
	print(`player {player.Name} has PowerService: {svc ~= nil}`)
end

print("executor smoke OK (run in a live session to exercise the remote path)")
```

Expected: prints `executor smoke OK` plus one line per connected player (empty if edit-mode only). No errors.

Note: full executor behavior (remote round-trip) is not covered by integration tests — per spec section 10, remote-level concerns are out of scope for this plan. Verify manually in a test session by firing the remote from a client shell and observing the response.

- [ ] **Step 3: Commit**

```bash
git add src/Server/PowerService/executor.server.lua
git commit -m "feat(powers): executor wires PlayerAdded/PlayerRemoving and remote handler"
```

---

### Task 6: Final verification

- [ ] **Step 1: Re-run the integration test**

Run via `mcp__robloxstudio__execute_luau`:

```lua
require(game:GetService("ServerScriptService").PowerService.integration_power_system)
```

Expected: `22 passed, 0 failed`. Fix and re-commit if anything regressed.

- [ ] **Step 2: Confirm file structure matches the spec**

Run in a shell:

```bash
find src/Shared/Power src/Server/PowerService -type f | sort
```

Expected output (10 files total):

```
src/Server/PowerService/Configs.lua
src/Server/PowerService/PowerRegistry.lua
src/Server/PowerService/Powers/.keep
src/Server/PowerService/Types.lua
src/Server/PowerService/executor.server.lua
src/Server/PowerService/init.lua
src/Server/PowerService/integration_power_system.test.lua
src/Shared/Power/PayloadValidator.lua
src/Shared/Power/PowerFailReason.lua
src/Shared/Power/Types.lua
```

Matches spec section 2.

- [ ] **Step 3: No tests or commits left hanging**

```bash
git status
git log --oneline -6
```

Expected: clean working tree, 5 new commits from this plan (one per task except task 6).

- [ ] **Step 4 (optional): Squash/amend if desired**

If you prefer a single commit for the entire feature, the user may ask you to interactively rebase the 5 commits into one. Do not do this unless asked — the per-task commit history is the default.

---

## Self-Review (performed by plan author)

**Spec coverage:**

- Spec §1 (Goal / non-goals) → Task 3 implements; Task 5 wires; no concrete Powers shipped ✓
- Spec §2 (File layout) → Every file created in Tasks 1-5; verified in Task 6 step 2 ✓
- Spec §3.1 (enum) → Task 1 step 1 ✓
- Spec §3.2 (shared types) → Task 1 step 2 ✓
- Spec §3.3 (API) → Task 3 step 1 ✓
- Spec §3.4 (instance fields) → Task 3 step 1 ✓
- Spec §4 (loadout resolution) → Task 3 step 1; plan notes the clarification (read moves to executor) ✓
- Spec §5 (`:Activate` flow) → Task 3 step 1, full implementation in code ✓
- Spec §6 (cooldown/debounce) → Task 2 step 1 (config) + Task 3 step 1 (logic) ✓
- Spec §7 (executor) → Task 5 step 1 ✓
- Spec §7.1 (remote handler) → Task 5 step 1 ✓
- Spec §8 (PayloadValidator) → Task 1 step 3 ✓
- Spec §9 (registry) → Task 2 step 3 ✓
- Spec §10 (testing — 14 cases) → Task 4 step 1 covers all 14, explicit case numbering ✓
- Spec §11 (constraints) → colon notation ✓, no silent returns (every gate returns a Result or warns) ✓, no Instance.new for UI (N/A) ✓, one file per responsibility ✓, fixed result shape ✓, no lifecycle tracking ✓
- Spec §12 (open/deferred) → No tasks needed; deliberate non-scope ✓

**Placeholder scan:** No TBDs, TODOs, "handle edge cases", or "similar to Task N" references found. Every step contains concrete code or commands.

**Type consistency:** `PowerFailReason` values, `PowerResult` shape, `Power` shape, and `ActivateRequest`/`Response` names match across shared types, server types, registry signatures, executor handler, and integration test. Method names (`.new`, `.Get`, `:Destroy`, `:Activate`, `_reset`) match between the class and the test.

**Deviations from spec worth the engineer's attention:**

1. **Loadout is passed into `.new`** rather than read from `TeleportMetadataService` inside `.new`. Executor does the read. Rationale documented at the top of Task 3.
2. **`PowerService._reset()`** test hook added. Follows the existing `PlayerReadiness._reset()` pattern already in the codebase. No production code path calls it.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-16-powers-system.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
