--// Run via mcp__robloxstudio__execute_luau in the edit environment.
--// Uses mock player tables since real Player objects are unavailable outside a session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RoundStateMachine = require(ServerScriptService.RoundService.RoundStateMachine)
local PlayerState = require(ServerScriptService.RoundService.PlayerState)
local TeamState = require(ServerScriptService.RoundService.TeamState)
local WinConditionEvaluator = require(ServerScriptService.RoundService.WinConditionEvaluator)
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

--// Mock player factory
local function mockPlayer(name: string, userId: number)
	return { Name = name, UserId = userId }
end

-- ─── RoundStateMachine ────────────────────────────────────────────────────────

do
	local sm = RoundStateMachine.new()
	local fired = false
	local capturedFrom, capturedTo

	sm:SetTransitionCallback(function(from, to)
		fired = true
		capturedFrom = from
		capturedTo = to
	end)

	sm:Transition(Configs.GAME_STATES.AssigningTeams)

	check("StateMachine: callback fires on valid transition", fired)
	check(
		"StateMachine: callback receives correct from/to",
		capturedFrom == Configs.GAME_STATES.WaitingForPlayers
			and capturedTo == Configs.GAME_STATES.AssigningTeams
	)
end

do
	local sm = RoundStateMachine.new()
	local fired = false
	sm:SetTransitionCallback(function() fired = true end)
	sm:Transition(Configs.GAME_STATES.RoundActive) -- illegal from WaitingForPlayers
	check("StateMachine: callback NOT fired on illegal transition", not fired)
end

-- ─── PlayerState ──────────────────────────────────────────────────────────────

do
	local p = mockPlayer("Alice", 1)
	local ps = PlayerState.new(p, 1)
	local data = ps:Serialize()

	check("PlayerState: initial status is Alive", data.status == Configs.PLAYER_STATUSES.Alive)
	check("PlayerState: initial team is correct", data.team == 1)
	check("PlayerState: initial kills = 0", data.stats.kills == 0)

	ps:SetAlive(false)
	check("PlayerState: SetAlive(false) → Dead", ps.status == Configs.PLAYER_STATUSES.Dead)

	ps:Reset()
	check("PlayerState: Reset → Alive", ps.status == Configs.PLAYER_STATUSES.Alive)
	check("PlayerState: Reset → kills zeroed", ps:GetStat("kills") == 0)
end

do
	local p = mockPlayer("Bob", 2)
	local ps = PlayerState.new(p, 2)

	ps:Lock()
	ps:SetAlive(false)
	check("PlayerState: Lock prevents SetAlive", ps.status == Configs.PLAYER_STATUSES.Alive)

	ps:Unlock()
	ps:SetAlive(false)
	check("PlayerState: Unlock allows SetAlive", ps.status == Configs.PLAYER_STATUSES.Dead)
end

do
	local p = mockPlayer("Carol", 3)
	local ps = PlayerState.new(p, 1)

	check("PlayerState: positionedThisRound defaults to false", ps.positionedThisRound == false)

	ps.positionedThisRound = true
	ps:Reset()
	check("PlayerState: Reset clears positionedThisRound", ps.positionedThisRound == false)
end

-- ─── TeamState ────────────────────────────────────────────────────────────────

do
	local p1 = mockPlayer("P1", 10)
	local p2 = mockPlayer("P2", 11)
	local p3 = mockPlayer("P3", 12)

	local playerStates = {}
	playerStates[p1] = PlayerState.new(p1, 1)    -- Alive
	playerStates[p2] = PlayerState.new(p2, 1)    -- Dead
	playerStates[p3] = PlayerState.new(p3, 1)    -- Disconnected

	playerStates[p2]:SetAlive(false)
	playerStates[p3].status = Configs.PLAYER_STATUSES.Disconnected

	local ts = TeamState.new(1, { p1, p2, p3 }, playerStates)
	local snap = ts:Recalculate()

	check("TeamState: alivePlayers = 1", snap.alivePlayers == 1)
	check("TeamState: deadPlayers = 1", snap.deadPlayers == 1)
	check("TeamState: disconnectedPlayers = 1", snap.disconnectedPlayers == 1)
end

do
	local p1 = mockPlayer("S1", 20)
	local p2 = mockPlayer("S2", 21)

	local playerStates = {}
	playerStates[p1] = PlayerState.new(p1, 1)    -- Alive
	playerStates[p2] = PlayerState.new(p2, 1)    -- Will be Skipped
	playerStates[p2].status = Configs.PLAYER_STATUSES.Skipped

	local ts = TeamState.new(1, { p1, p2 }, playerStates)
	local snap = ts:Recalculate()

	check("TeamState: Skipped does not count as alive", snap.alivePlayers == 1)
	check("TeamState: Skipped exposed as skippedPlayers", snap.skippedPlayers == 1)
	check("TeamState: Skipped counted in totalPlayerCount", snap.totalPlayerCount == 2)
end

-- ─── WinConditionEvaluator ────────────────────────────────────────────────────

local function teamSnap(team: number, alive: number)
	return { teamNumber = team, alivePlayers = alive, deadPlayers = 0, disconnectedPlayers = 0,
		totalPlayerCount = alive, originalPlayerCount = alive, points = 0 }
end

do
	local over, winner = WinConditionEvaluator.isRoundOver(teamSnap(1, 1), teamSnap(2, 1))
	check("WinCondition: both alive → not over", not over)

	over, winner = WinConditionEvaluator.isRoundOver(teamSnap(1, 0), teamSnap(2, 1))
	check("WinCondition: team1 = 0 alive → team2 wins", over and winner == 2)

	over, winner = WinConditionEvaluator.isRoundOver(teamSnap(1, 1), teamSnap(2, 0))
	check("WinCondition: team2 = 0 alive → team1 wins", over and winner == 1)

	over, winner = WinConditionEvaluator.isRoundOver(teamSnap(1, 0), teamSnap(2, 0))
	check("WinCondition: both = 0 alive → over, no winner", over and winner == nil)
end

do
	local results = { { winningTeam = 1 }, { winningTeam = 1 } }
	local over, winner = WinConditionEvaluator.isGameOver(results, 2)
	check("WinCondition: team1 reaches ROUNDS_TO_WIN → game over", over and winner == 1)
end

do
	--// MAX_ROUNDS reached, teams tied
	local results = { { winningTeam = 1 }, { winningTeam = 2 }, { winningTeam = nil } }
	local over, winner = WinConditionEvaluator.isGameOver(results, Configs.MAX_ROUNDS)
	check("WinCondition: MAX_ROUNDS with tie → game over, no winner", over and winner == nil)
end

-- ─── Summary ──────────────────────────────────────────────────────────────────

print(`\n{passed} passed, {failed} failed`)
