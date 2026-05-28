local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local Configs = require(ReplicatedStorage.Round.Configs)

local RoundService = require(script.Parent)
local TeleportDataValidator = require(script.Parent.TeleportDataValidator)
local PlayerReadiness = require(script.Parent.PlayerReadiness)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local DataService = require(ServerScriptService.DataService)
local ReconnectService = require(ServerScriptService.ReconnectService)

local roundSystem = nil
local handled = setmetatable({}, { __mode = "k" }) :: { [Player]: boolean }



ServerEventBus:Connect("ProfileLoaded", function(player: Player)
	PlayerReadiness.recordFact(player, "ProfileLoaded")
end, { replayLast = true })

local function buildTemplateTeleportData()
	return {
		teamOnePlayers = {},
		teamTwoPlayers = {},
		expectedPlayersPerTeam = 1,
		queueType = 1,
		mapName = "TestMap",
		timestamp = os.time(),
	}
end

local function setupPlayer(player: Player)
	if handled[player] then
		warn(`[RoundService.executor] setup skipped for {player.Name}: already handled`)
		return
	end
	handled[player] = true

	PlayerReadiness.ensureRecord(player)
	if DataService:IsProfileLoaded(player) then
		PlayerReadiness.recordFact(player, "ProfileLoaded")
	end

	local teleportData
	local joinData = player:GetJoinData()
	local rawData = joinData and joinData.TeleportData

	if type(rawData) == "table" and rawData.reconnect == true then
		if not roundSystem then
			warn(`[Round] Reconnect rejected for {player.Name}: no active round system`)
			ReconnectService.ReturnPlayerToLobby(player, "ReconnectUnavailable")
			return
		end

		local ok, ticketOrReason = ReconnectService.ValidateReconnect(player, rawData, roundSystem:GetMatchId())
		if not ok then
			warn(`[Round] Reconnect rejected for {player.Name}: {ticketOrReason}`)
			ReconnectService.ReturnPlayerToLobby(player, tostring(ticketOrReason))
			return
		end

		local registered, registerReason = roundSystem:RegisterReconnect(player, ticketOrReason)
		if not registered then
			warn(`[Round] RegisterReconnect rejected for {player.Name}: {registerReason}`)
			ReconnectService.ReturnPlayerToLobby(player, registerReason)
			return
		end
		return
	end

	if GlobalConfigs.TEST_MODE then
		print(`[Round] TEST_MODE — {player.Name} using template data (map: TestMap, 1v1)`)
		teleportData = buildTemplateTeleportData()
	else
		local ok, err, sanitized = TeleportDataValidator.validate(rawData)
		if not ok then
			warn(`[Round] Invalid teleport data for {player.Name}: {err}`)
			player:Kick(Configs.KICK_REASONS.InvalidTeleportData)
			return
		end
		teleportData = sanitized
	end

	if not roundSystem then
		local expected = if type(teleportData.expectedPlayersPerTeam) == "number"
			then teleportData.expectedPlayersPerTeam * 2
			else #teleportData.teamOnePlayers + #teleportData.teamTwoPlayers
		print(`[Round] Creating RoundSystem — map: {teleportData.mapName}, expecting {expected} player(s)`)
		roundSystem = RoundService.new(teleportData)
		if GlobalConfigs.TEST_MODE then
			_G._testRoundSystem = roundSystem
		end
	elseif not GlobalConfigs.TEST_MODE then
		if teleportData.matchId ~= roundSystem:GetMatchId() then
			warn(`[Round] Join rejected for {player.Name}: match id mismatch`)
			player:Kick(Configs.KICK_REASONS.InvalidTeleportData)
			return
		end
		if not roundSystem:ContainsExpectedUserId(player.UserId) then
			warn(`[Round] Join rejected for {player.Name}: not in original roster`)
			player:Kick(Configs.KICK_REASONS.InvalidTeleportData)
			return
		end
	end

	if roundSystem:GetState() ~= Configs.GAME_STATES.WaitingForPlayers then
		warn(`[Round] Join rejected for {player.Name}: match already started`)
		player:Kick(Configs.KICK_REASONS.InvalidTeleportData)
		return
	end

	
	
	player.CharacterAdded:Connect(function(character)
		if roundSystem:GetState() == Configs.GAME_STATES.WaitingForPlayers then
			local rootPart = character:WaitForChild("HumanoidRootPart", Configs.CHAR_FACT_WAIT_TIMEOUT)
			if rootPart then
				local spawnBox = workspace:FindFirstChild(Configs.INITIAL_SPAWN_PART)
				if spawnBox then
					local half = spawnBox.Size / 2
					local rx = (math.random() * 2 - 1) * half.X
					local rz = (math.random() * 2 - 1) * half.Z
					rootPart.CFrame = spawnBox.CFrame * CFrame.new(rx, half.Y + 3, rz)
					print(`[Round] {player.Name} spawned in InitialSpawnBox`)
				else
					warn("[Round] InitialSpawnBox not found in workspace")
				end
			end
		end

		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			roundSystem:OnPlayerDied(player)
		end)
	end)

	roundSystem:RegisterPlayer(player)

	
	
	
	
	if roundSystem:GetState() == Configs.GAME_STATES.WaitingForPlayers then
		player:LoadCharacter()
	end
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	if roundSystem then
		roundSystem:UnregisterPlayer(player)
	end
	PlayerReadiness.destroyRecord(player)
end)
