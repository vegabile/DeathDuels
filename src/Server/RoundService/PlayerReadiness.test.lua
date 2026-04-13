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
	check("waitForChange: respects timeout", elapsed >= 0.15 and elapsed < 0.4)
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

print(`\n{passed} passed, {failed} failed`)
