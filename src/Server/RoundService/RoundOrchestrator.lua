local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local PlayerState = require(script.Parent.PlayerState)
local TeamState = require(script.Parent.TeamState)
local WinConditionEvaluator = require(script.Parent.WinConditionEvaluator)
local TeleportMetadataService = require(script.Parent.TeleportMetadataService)
local TeleportUtility = require(script.Parent.TeleportUtility)

local RoundOrchestrator = {}

local function collectSpawnParts(mapModel)
	local red = {}
	local blue = {}
	for _, desc in mapModel:GetDescendants() do
		if desc.Name == Configs.SPAWN_PARTS.Red then
			table.insert(red, desc)
		elseif desc.Name == Configs.SPAWN_PARTS.Blue then
			table.insert(blue, desc)
		end
	end
	return red, blue
end

local function getSpawnAssignment(system)
	local red, blue = collectSpawnParts(system._mapModel)
	--// Alternate each round: odd → team1=red, even → team1=blue
	if system._roundNumber % 2 == 1 then
		return { [1] = red, [2] = blue }
	else
		return { [1] = blue, [2] = red }
	end
end

local function loadAndPositionPlayers(system)
	local spawnGroups = getSpawnAssignment(system)

	for teamNum, spawns in spawnGroups do
		if #spawns == 0 then
			warn(`[RoundOrchestrator] No spawn parts found for team {teamNum}`)
			continue
		end
		local players = system._teamPlayers[teamNum]
		for i, player in players do
			if not system._playerStates[player] then continue end

			local spawnPart = spawns[((i - 1) % #spawns) + 1]

			if not player.Character or not player.Character:FindFirstChild("Humanoid") or player.Character.Humanoid.Health <= 0 then
				player:LoadCharacter()
			end

			local character = player.Character or player.CharacterAdded:Wait()
			local rootPart = character:WaitForChild("HumanoidRootPart", Configs.CHARACTER_LOAD_TIMEOUT)
			if rootPart then
				rootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
			else
				warn(`[RoundOrchestrator] Character load timed out for {player.Name}`)
			end
		end
	end
end

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

	--// Load map
	local mapName = TeleportMetadataService.GetMapName()
	local mapsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Maps")
	local mapTemplate = mapsFolder and mapsFolder:FindFirstChild(mapName)
	if not mapTemplate then
		warn(`[RoundOrchestrator] Map "{mapName}" not found, aborting`)
		system:_transition(Configs.GAME_STATES.Aborted)
		return
	end
	system._mapModel = mapTemplate:Clone()
	system._mapModel.Parent = workspace

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

	task.spawn(function()
		system._positioningPlayers = true
		loadAndPositionPlayers(system)
		system._positioningPlayers = false
		system:_broadcastUpdate()

		system._roundTimerTask = task.delay(Configs.ROUND_DURATION, function()
			system._roundTimerTask = nil
			if system._stateMachine:GetState() ~= Configs.GAME_STATES.RoundActive then return end

			--// Time expired — determine winner by alive count
			local t1 = system._teamStates[1]:Recalculate()
			local t2 = system._teamStates[2]:Recalculate()

			local winningTeam = nil
			if t1.alivePlayers > t2.alivePlayers then
				winningTeam = 1
			elseif t2.alivePlayers > t1.alivePlayers then
				winningTeam = 2
			end

			table.insert(system._roundResults, { winningTeam = winningTeam, stats = {} })
			system:_fireEvent("RoundOver", winningTeam, system._roundNumber)

			local gameOver = WinConditionEvaluator.isGameOver(system._roundResults, system._roundNumber)
			if gameOver then
				system:_transition(Configs.GAME_STATES.GameOver)
			else
				system:_transition(Configs.GAME_STATES.RoundIntermission)
			end
		end)
	end)
end

local function enterRoundIntermission(system)
	if system._roundTimerTask then
		task.cancel(system._roundTimerTask)
		system._roundTimerTask = nil
	end

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
	ServerEventBus:Fire("RoundStateChanged", state)

	local handler = handlers[state]
	if not handler then
		warn(`[RoundOrchestrator] No handler for state: {state}`)
		return
	end
	local ok, err = pcall(handler, system)
	if not ok then
		warn(`[RoundOrchestrator] Handler error in state {state}: {err}`)
		if state ~= Configs.GAME_STATES.Aborted and state ~= Configs.GAME_STATES.TeleportingOut then
			system:_transition(Configs.GAME_STATES.Aborted)
		end
	end
end

return RoundOrchestrator
