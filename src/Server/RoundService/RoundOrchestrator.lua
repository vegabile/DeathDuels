local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configs = require(ReplicatedStorage.Round.Configs)
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local SharedPowerConfigs = require(ReplicatedStorage.Power.Configs)
local PowerService = require(ServerScriptService.PowerService)
local WeaponDistributor = require(ServerScriptService.WeaponDistributor)

local PlayerState = require(script.Parent.PlayerState)
local TeamState = require(script.Parent.TeamState)
local WinConditionEvaluator = require(script.Parent.WinConditionEvaluator)
local TeleportMetadataService = require(script.Parent.TeleportMetadataService)
local TeleportUtility = require(script.Parent.TeleportUtility)
local PlayerReadiness = require(script.Parent.PlayerReadiness)

local RoundOrchestrator = {}

local function setPowerRoundEligible(player: Player, eligible: boolean)
	player:SetAttribute(SharedPowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE, eligible)
	player:SetAttribute(Configs.COMBAT_ELIGIBLE_ATTRIBUTE, eligible)
end

local function collectSpawnParts(mapModel)
	local red = {}
	local blue = {}
	for _, desc in mapModel:GetDescendants() do
		if desc.Name == Configs.SPAWN_PARTS.Red and desc:IsA("BasePart") then
			table.insert(red, desc)
		elseif desc.Name == Configs.SPAWN_PARTS.Blue and desc:IsA("BasePart") then
			table.insert(blue, desc)
		end
	end
	return red, blue
end

local function getSpawnAssignment(system)
	local red, blue = collectSpawnParts(system._mapModel)
	
	if system._roundNumber % 2 == 1 then
		return { [1] = red, [2] = blue }
	else
		return { [1] = blue, [2] = red }
	end
end






local function loadCharacterAndRecord(player: Player, timeout: number): boolean
	local token = PlayerReadiness.beginCharacterLoad(player)

	local characterResult: Model? = nil
	local characterSignal = Instance.new("BindableEvent")
	local conn = player.CharacterAdded:Once(function(c)
		characterResult = c
		characterSignal:Fire()
	end)

	local loadOk = pcall(function() player:LoadCharacter() end)
	if not loadOk then
		conn:Disconnect()
		characterSignal:Destroy()
		warn(`[Round] loadCharacterAndRecord: LoadCharacter threw for {player.Name}`)
		return false
	end

	if not characterResult then
		local timer = task.delay(timeout, function()
			characterSignal:Fire()
		end)
		characterSignal.Event:Wait()
		task.cancel(timer)
	end
	characterSignal:Destroy()

	if not characterResult then
		conn:Disconnect()
		return false
	end

	local character = characterResult :: Model
	local hrp = character:WaitForChild("HumanoidRootPart", Configs.CHAR_FACT_WAIT_TIMEOUT)
	local humanoid = character:WaitForChild("Humanoid", Configs.CHAR_FACT_WAIT_TIMEOUT)
	if not hrp or not humanoid then
		return false
	end
	if hrp:IsA("BasePart") and character.PrimaryPart == nil then
		character.PrimaryPart = hrp
	end

	PlayerReadiness.recordCharacterFact(player, token, "CharacterLoaded")
	PlayerReadiness.recordCharacterFact(player, token, "CharacterUsable")
	return true
end

local function clearBackpack(player: Player)
	local backpack = player:FindFirstChildWhichIsA("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then child:Destroy() end
		end
	end
	local character = (player :: any).Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then child:Destroy() end
		end
	end
end

local function pickInitialSpawnCFrame(): CFrame
	local spawnBox = workspace:FindFirstChild(Configs.INITIAL_SPAWN_PART)
	if spawnBox and spawnBox:IsA("BasePart") then
		local half = spawnBox.Size / 2
		local rx = (math.random() * 2 - 1) * half.X
		local rz = (math.random() * 2 - 1) * half.Z
		return spawnBox.CFrame * CFrame.new(rx, half.Y + 3, rz)
	end
	warn("[Round] InitialSpawnBox missing — falling back to (0, 100, 0)")
	return CFrame.new(0, 100, 0)
end





local function applySkipped(system, player: Player, playerState)
	if playerState.status == Configs.PLAYER_STATUSES.Skipped then
		setPowerRoundEligible(player, false)
		return
	end
	playerState.status = Configs.PLAYER_STATUSES.Skipped
	playerState:SetInGame(false)
	setPowerRoundEligible(player, false)

	clearBackpack(player)

	local character = (player :: any).Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if hrp and hrp:IsA("BasePart") then
			hrp.CFrame = pickInitialSpawnCFrame()
			hrp.Anchored = true
		end
		if humanoid then
			humanoid.WalkSpeed = 0
		end
		if not character:FindFirstChildOfClass("ForceField") then
			local ff = Instance.new("ForceField")
			ff.Visible = true
			ff.Parent = character
		end
	else
		warn(`[Round] applySkipped: {player.Name} has no character; physical side effects deferred until next character load`)
	end

	system:_broadcastUpdate()
end





local function exitSkippedOrPosition(system, player: Player, playerState, spawnPart: BasePart, loadout): boolean
	if playerState.positionedThisRound then return true end
	local character = (player :: any).Character
	if not character then
		setPowerRoundEligible(player, false)
		warn(`[Round] exitSkippedOrPosition: {player.Name} has no character; cannot position`)
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (hrp and hrp:IsA("BasePart") and humanoid) then
		setPowerRoundEligible(player, false)
		warn(`[Round] exitSkippedOrPosition: {player.Name} missing HRP or Humanoid`)
		return false
	end

	hrp.Anchored = false
	hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	if character.PrimaryPart == nil then
		character.PrimaryPart = hrp
	end
	humanoid.WalkSpeed = Configs.DEFAULT_WALK_SPEED

	for _, child in character:GetChildren() do
		if child:IsA("ForceField") then child:Destroy() end
	end

	local knifeName = loadout and loadout.knifeName
	local gunName = loadout and loadout.gunName
	WeaponDistributor.distributeToPlayer(player, knifeName, gunName)
	playerState.positionedThisRound = true
	playerState.status = Configs.PLAYER_STATUSES.Alive
	playerState:SetInGame(true)
	setPowerRoundEligible(player, true)
	return true
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

	local mapName = TeleportMetadataService.GetMapName()
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
		local playerState = PlayerState.new(player, team)
		system._playerStates[player] = playerState
		system._playerStatesByUserId[player.UserId] = playerState
		system._playersByUserId[player.UserId] = player
		table.insert(system._teamPlayers[team], player)
	end
	system._teamStates[1] = TeamState.new(1, system._teamPlayers[1], system._playerStates)
	system._teamStates[2] = TeamState.new(2, system._teamPlayers[2], system._playerStates)

	
	
	
	local roster: { Player } = {}
	for _, p in system._teamPlayers[1] do table.insert(roster, p) end
	for _, p in system._teamPlayers[2] do table.insert(roster, p) end
	system._roundRoster = roster

	
	for _, p in roster do
		PowerService.AssignLoadout(p, if GlobalConfigs.TEST_MODE then Configs.DEFAULT_LOADOUT else TeleportMetadataService.GetLoadout(p.UserId))
		PlayerReadiness.recordFact(p, "LoadoutResolved")
	end

	
	system._pendingPlayers = {}

	system:_transition(Configs.GAME_STATES.PreparingPlayers)
end

local function allRosterReady(roster: { Player }): boolean
	for _, player in roster do
		if not PlayerReadiness.isComplete(player) then return false end
	end
	return true
end

local function enterPreparingPlayers(system)
	local deadline = os.clock() + Configs.READINESS_GRACE_FIRST_ROUND

	
	
	
	
	for _, player in system._roundRoster do
		task.spawn(function()
			loadCharacterAndRecord(player, Configs.READINESS_GRACE_FIRST_ROUND)
		end)
	end

	
	while true do
		if allRosterReady(system._roundRoster) then break end
		local timeLeft = deadline - os.clock()
		if timeLeft <= 0 then break end
		PlayerReadiness.waitForChange(timeLeft)
		if system._stateMachine:GetState() ~= Configs.GAME_STATES.PreparingPlayers then return end
	end

	
	
	for _, player in system._roundRoster do
		if not PlayerReadiness.isComplete(player) then
			warn(`[Round] {player.Name} incomplete after PreparingPlayers grace: {table.concat(PlayerReadiness.missingFacts(player), ", ")}`)
			applySkipped(system, player, system._playerStates[player])
		end
	end

	system:_transition(Configs.GAME_STATES.RoundActive)
end

local function enterRoundActive(system)
	local roundToken = system._roundToken
	system._positioningPlayers = true

	
	
	system._roundTimerTask = task.delay(Configs.ROUND_DURATION, function()
		system._roundTimerTask = nil
		if system._stateMachine:GetState() ~= Configs.GAME_STATES.RoundActive then return end
		if system._roundToken ~= roundToken then return end

		
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

	local remaining = 0
	local finalized = false
	local function isCurrentRound()
		return system._roundToken == roundToken
			and system._stateMachine:GetState() == Configs.GAME_STATES.RoundActive
	end

	local function finalize()
		if finalized then return end
		if not isCurrentRound() then return end
		finalized = true
		system._positioningPlayers = false
		system:_broadcastUpdate()
		system:_checkWinCondition()
	end

	
	local spawnGroups = getSpawnAssignment(system)

	for teamNum, players in system._teamPlayers do
		local spawns = spawnGroups[teamNum]
		if not spawns or #spawns == 0 then
			warn(`[Round] No spawn parts found for team {teamNum}`)
			continue
		end
		for i, player in players do
			local playerState = system._playerStates[player]
			if not playerState then continue end
			if playerState.status == Configs.PLAYER_STATUSES.Disconnected then continue end
			if playerState.status == Configs.PLAYER_STATUSES.Skipped then
				
				
				continue
			end
			playerState.status = Configs.PLAYER_STATUSES.Positioning
			playerState:SetInGame(false)
			playerState.positionedThisRound = false

			local spawnPart = spawns[((i - 1) % #spawns) + 1]
			remaining += 1

			task.spawn(function()
				local ok, err = pcall(function()
					if not isCurrentRound() or finalized then return end
					
					
					
					if not PlayerReadiness.isComplete(player) then
						local ready = loadCharacterAndRecord(player, Configs.LATE_TELEPORT_GRACE)
						if not isCurrentRound() or finalized then return end
						if not ready then
							applySkipped(system, player, playerState)
							return
						end
					end
					local loadout = if GlobalConfigs.TEST_MODE then Configs.DEFAULT_LOADOUT else TeleportMetadataService.GetLoadout(player.UserId)
					if not exitSkippedOrPosition(system, player, playerState, spawnPart, loadout) then
						applySkipped(system, player, playerState)
					end
				end)
				if not ok and isCurrentRound() and not finalized then
					warn(`[Round] Positioning task errored for {player.Name}: {err}`)
					applySkipped(system, player, playerState)
				end
				remaining -= 1
				if remaining == 0 then finalize() end
			end)
		end
	end

	if remaining == 0 then finalize() end   

	
	task.delay(Configs.POSITIONING_OUTER_TIMEOUT, function()
		if finalized then return end
		if not isCurrentRound() then return end
		warn("[Round] Positioning outer safety timer fired — force-finalizing")
		for _, player in system._roundRoster do
			local state = system._playerStates[player]
			if not state then continue end
			local s = state.status
			if not state.positionedThisRound
				and s ~= Configs.PLAYER_STATUSES.Skipped
				and s ~= Configs.PLAYER_STATUSES.Disconnected
			then
				warn(`[Round] {player.Name} was not positioned before timeout — forcing Skipped`)
				applySkipped(system, player, state)
			end
		end
		finalize()
	end)
end

local function enterRoundIntermission(system)
	if system._roundTimerTask then
		task.cancel(system._roundTimerTask)
		system._roundTimerTask = nil
	end

	local lastResult = system._roundResults[#system._roundResults]
	local winner = lastResult and lastResult.winningTeam
	for _, playerState in system._playerStates do
		setPowerRoundEligible(playerState.player, false)
		playerState:Lock()
	end

	system:_broadcastUpdate()

	system._waitTask = task.delay(Configs.ROUND_INTERMISSION_DURATION, function()
		system._waitTask = nil

		for _, playerState in system._playerStates do
			if playerState.status == Configs.PLAYER_STATUSES.Disconnected then
				
				continue
			end
			setPowerRoundEligible(playerState.player, false)
			playerState:Unlock()
			playerState:Reset()   
		end

		
		
		for _, player in system._roundRoster do
			PlayerReadiness.clearFact(player, "CharacterLoaded")
			PlayerReadiness.clearFact(player, "CharacterUsable")
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
	local _, overallWinner = WinConditionEvaluator.isGameOver(system._roundResults, system._roundNumber)
	local payload = TeleportUtility.buildReturnPayload(system._playerStates, system._roundResults, overallWinner, system._disconnectedStats, system:GetMatchId())
	local ok, err = TeleportUtility.teleportPlayersWithRetry(players, Configs.LOBBY_PLACE_ID, payload)
	if not ok then
		warn(`[Round] Teleport failed after retries: {err}`)
	end
end

local function enterAborted(system)
	system:_transition(Configs.GAME_STATES.TeleportingOut)
end

local handlers = {
	[Configs.GAME_STATES.WaitingForPlayers] = enterWaitingForPlayers,
	[Configs.GAME_STATES.AssigningTeams] = enterAssigningTeams,
	[Configs.GAME_STATES.PreparingPlayers] = enterPreparingPlayers,
	[Configs.GAME_STATES.RoundActive] = enterRoundActive,
	[Configs.GAME_STATES.RoundIntermission] = enterRoundIntermission,
	[Configs.GAME_STATES.GameOver] = enterGameOver,
	[Configs.GAME_STATES.TeleportingOut] = enterTeleportingOut,
	[Configs.GAME_STATES.Aborted] = enterAborted,
}

function RoundOrchestrator.enter(state: string, system)
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



RoundOrchestrator.ApplySkipped = applySkipped
RoundOrchestrator.SetPowerRoundEligible = setPowerRoundEligible

return RoundOrchestrator
