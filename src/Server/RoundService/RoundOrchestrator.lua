local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Round.Configs)

local PlayerState = require(script.Parent.PlayerState)
local TeamState = require(script.Parent.TeamState)
local WinConditionEvaluator = require(script.Parent.WinConditionEvaluator)
local TeleportMetadataService = require(script.Parent.TeleportMetadataService)
local TeleportUtility = require(script.Parent.TeleportUtility)

local RoundOrchestrator = {}

local function enterWaitingForPlayers(system)
	system._waitTask = task.delay(Configs.WAITING_PERIOD, function()
		if system._stateMachine:GetState() == Configs.GAME_STATES.WaitingForPlayers then
			system:_transition(Configs.GAME_STATES.AssigningTeams)
		end
	end)
end

local function enterAssigningTeams(system)
	if system._waitTask then
		task.cancel(system._waitTask)
		system._waitTask = nil
	end

	system._teamPlayers = { [1] = {}, [2] = {} }

	for _, player in system._pendingPlayers do
		local team = TeleportMetadataService.GetTeam(player)
		if not team then
			warn(`[RoundOrchestrator] No team found for {player.Name}, skipping`)
			continue
		end
		system._playerStates[player] = PlayerState.new(player, team)
		table.insert(system._teamPlayers[team], player)
	end

	system._teamStates[1] = TeamState.new(1, system._teamPlayers[1], system._playerStates)
	system._teamStates[2] = TeamState.new(2, system._teamPlayers[2], system._playerStates)

	system:_transition(Configs.GAME_STATES.RoundActive)
end

local function enterRoundActive(system)
	system._roundNumber += 1
end

local function enterRoundIntermission(system)
	for _, playerState in system._playerStates do
		playerState:Lock()
	end

	system:_broadcastUpdate()

	system._waitTask = task.delay(Configs.ROUND_INTERMISSION_DURATION, function()
		system._waitTask = nil

		for _, playerState in system._playerStates do
			playerState:Unlock()
			playerState:Reset()
		end

		local isOver = WinConditionEvaluator.isGameOver(system._roundResults, system._roundNumber)
		if isOver then
			system:_transition(Configs.GAME_STATES.GameOver)
		else
			system:_transition(Configs.GAME_STATES.RoundActive)
		end
	end)
end

local function enterGameOver(system)
	local lastResult = system._roundResults[#system._roundResults]
	system:_fireEvent("GameOver", lastResult and lastResult.winningTeam or nil)

	system._waitTask = task.delay(Configs.GAME_OVER_DURATION, function()
		system._waitTask = nil
		system:_transition(Configs.GAME_STATES.TeleportingOut)
	end)
end

local function enterTeleportingOut(system)
	local players = {}
	for player in system._playerStates do
		table.insert(players, player)
	end

	local payload = TeleportUtility.buildReturnPayload(system._playerStates, system._roundResults, nil)
	local ok, err = TeleportUtility.teleportPlayersWithRetry(players, Configs.LOBBY_PLACE_ID, payload)
	if not ok then
		warn(`[RoundOrchestrator] Teleport failed after retries: {err}`)
	end
end

local function enterAborted(system)
	system:_transition(Configs.GAME_STATES.TeleportingOut)
end

local handlers = {
	[Configs.GAME_STATES.WaitingForPlayers] = enterWaitingForPlayers,
	[Configs.GAME_STATES.AssigningTeams] = enterAssigningTeams,
	[Configs.GAME_STATES.RoundActive] = enterRoundActive,
	[Configs.GAME_STATES.RoundIntermission] = enterRoundIntermission,
	[Configs.GAME_STATES.GameOver] = enterGameOver,
	[Configs.GAME_STATES.TeleportingOut] = enterTeleportingOut,
	[Configs.GAME_STATES.Aborted] = enterAborted,
}

function RoundOrchestrator.enter(state: string, system)
	local handler = handlers[state]
	if not handler then
		warn(`[RoundOrchestrator] No handler for state: {state}`)
		return
	end
	handler(system)
end

return RoundOrchestrator
