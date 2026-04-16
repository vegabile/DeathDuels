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
