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
	local char, hum = mockCharacter(opts.health or 100)
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

--// overrides.name must be lowercase — makeRegistry stores it verbatim while
--// :Activate lowercases before lookup, so a mixed-case name would silently
--// miss the registry.
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
