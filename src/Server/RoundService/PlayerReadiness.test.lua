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

print(`\n{passed} passed, {failed} failed`)
