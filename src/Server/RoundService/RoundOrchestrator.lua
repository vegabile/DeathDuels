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
	local remaining = 0
	local doneEvent = system._positioningDoneEvent

	for teamNum, spawns in spawnGroups do
		local players = system._teamPlayers[teamNum]
		if #spawns == 0 then
			warn(`[Round] No spawn parts found for team {teamNum}`)
			continue
		end
		for i, player in players do
			if not system._playerStates[player] then
				warn(`[Round] {player.Name} skipped — no playerState`)
				continue
			end
			remaining += 1
			local spawnPart = spawns[((i - 1) % #spawns) + 1]

			task.spawn(function()
				local deadline = os.clock() + Configs.CHARACTER_LOAD_TIMEOUT

				--// LoadCharacter throws if the player disconnects mid-call.
				pcall(function()
					if not player.Character
						or not player.Character:FindFirstChild("Humanoid")
						or player.Character.Humanoid.Health <= 0
					then
						player:LoadCharacter()
					end
				end)

				--// Wait for the character model itself (may already exist).
				local character = player.Character
				if not character and player.Parent then
					local result
					local conn = player.CharacterAdded:Connect(function(c)
						result = c
					end)
					while not result and os.clock() < deadline and player.Parent do
						task.wait()
					end
					conn:Disconnect()
					character = result
				end

				--// Wait for HumanoidRootPart to replicate within the remaining
				--// deadline. CharacterAdded can fire before HRP is available,
				--// so the HRP wait is the real "usable character" signal.
				local rootPart
				if character and player.Parent then
					local timeLeft = deadline - os.clock()
					if timeLeft > 0 then
						rootPart = character:WaitForChild("HumanoidRootPart", timeLeft)
					end
				end

				if rootPart then
					rootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
					print(`[Round] {player.Name} → Team {teamNum} → {spawnPart.Name}`)
				else
					warn(`[Round] Character load timed out for {player.Name} — kicking`)
					if player.Parent then
						player:Kick(Configs.KICK_REASONS.CharacterLoadTimeout)
					end
				end

				remaining -= 1
				if remaining == 0 then
					doneEvent:Fire()
				end
			end)
		end
	end

	if remaining > 0 then
		doneEvent.Event:Wait()
	end
end

local function enterWaitingForPlayers(system)
	print(`[Round] State: WaitingForPlayers — fallback in {Configs.WAITING_PERIOD}s`)
	system._waitTask = task.delay(Configs.WAITING_PERIOD, function()
		if system._stateMachine:GetState() == Configs.GAME_STATES.WaitingForPlayers then
			print("[Round] Wait period elapsed — advancing to AssigningTeams")
			system:_transition(Configs.GAME_STATES.AssigningTeams)
		end
	end)
end

local function enterAssigningTeams(system)
	if system._waitTask then
		task.cancel(system._waitTask)
		system._waitTask = nil
	end

	local mapName = TeleportMetadataService.GetMapName()
	print(`[Round] State: AssigningTeams — map: "{mapName}"`)

	local mapsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Maps")
	local mapTemplate = mapsFolder and mapsFolder:FindFirstChild(mapName)
	if not mapTemplate then
		warn(`[Round] Map "{mapName}" not found — aborting`)
		system:_transition(Configs.GAME_STATES.Aborted)
		return
	end
	system._mapModel = mapTemplate:Clone()
	system._mapModel.Parent = workspace

	system._teamPlayers = { [1] = {}, [2] = {} }

	for _, player in system._pendingPlayers do
		local team = TeleportMetadataService.GetTeam(player)
		if not team then
			local t1 = #system._teamPlayers[1]
			local t2 = #system._teamPlayers[2]
			team = (t1 <= t2) and 1 or 2
			warn(`[Round] {player.Name} had no team — dynamically assigned to team {team}`)
			TeleportMetadataService.SetTeam(player.UserId, team)
		end
		system._playerStates[player] = PlayerState.new(player, team)
		table.insert(system._teamPlayers[team], player)
	end

	print(`[Round] Team 1: {#system._teamPlayers[1]} player(s) | Team 2: {#system._teamPlayers[2]} player(s)`)

	system._teamStates[1] = TeamState.new(1, system._teamPlayers[1], system._playerStates)
	system._teamStates[2] = TeamState.new(2, system._teamPlayers[2], system._playerStates)

	system:_transition(Configs.GAME_STATES.RoundActive)
end

local function enterRoundActive(system)
	system._roundNumber += 1
	print(`[Round] State: RoundActive — Round {system._roundNumber} | {Configs.ROUND_DURATION}s`)

	task.spawn(function()
		system._positioningPlayers = true
		loadAndPositionPlayers(system)
		system._positioningPlayers = false
		system:_broadcastUpdate()
		system:_checkWinCondition()

		if system._stateMachine:GetState() ~= Configs.GAME_STATES.RoundActive then return end

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

			print(`[Round] Time expired — winner: {winningTeam and "Team "..winningTeam or "Draw"}`)

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

	local lastResult = system._roundResults[#system._roundResults]
	local winner = lastResult and lastResult.winningTeam
	print(`[Round] State: RoundIntermission — Round {system._roundNumber} winner: {winner and "Team "..winner or "Draw"} | {Configs.ROUND_INTERMISSION_DURATION}s`)

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
	local winner = lastResult and lastResult.winningTeam
	print(`[Round] State: GameOver — Overall winner: {winner and "Team "..winner or "No winner"} | Teleporting in {Configs.GAME_OVER_DURATION}s`)

	system:_fireEvent("GameOver", winner)

	system._waitTask = task.delay(Configs.GAME_OVER_DURATION, function()
		system._waitTask = nil
		system:_transition(Configs.GAME_STATES.TeleportingOut)
	end)
end

local function enterTeleportingOut(system)
	local players = {}
	local seen = {}

	for player in system._playerStates do
		if not seen[player] and player.Parent ~= nil then
			seen[player] = true
			table.insert(players, player)
		end
	end

	for _, player in system._pendingPlayers do
		if not seen[player] and player.Parent ~= nil then
			seen[player] = true
			table.insert(players, player)
		end
	end

	print(`[Round] State: TeleportingOut — {#players} player(s)`)

	local _, overallWinner = WinConditionEvaluator.isGameOver(system._roundResults, system._roundNumber)
	local payload = TeleportUtility.buildReturnPayload(system._playerStates, system._roundResults, overallWinner, system._disconnectedStats)
	local ok, err = TeleportUtility.teleportPlayersWithRetry(players, Configs.LOBBY_PLACE_ID, payload)
	if not ok then
		warn(`[Round] Teleport failed after retries: {err}`)
	end
end

local function enterAborted(system)
	print("[Round] State: Aborted — transitioning to TeleportingOut")
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
		warn(`[Round] No handler for state: {state}`)
		return
	end
	local ok, err = pcall(handler, system)
	if not ok then
		warn(`[Round] Handler error in state {state}: {err}`)
		if state ~= Configs.GAME_STATES.Aborted and state ~= Configs.GAME_STATES.TeleportingOut then
			system:_transition(Configs.GAME_STATES.Aborted)
		end
	end
end

return RoundOrchestrator
