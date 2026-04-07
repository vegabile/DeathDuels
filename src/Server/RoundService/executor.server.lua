local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local Configs = require(ReplicatedStorage.Round.Configs)

local RoundService = require(script.Parent)
local TeleportDataValidator = require(script.Parent.TeleportDataValidator)

local roundSystem = nil

local function buildTemplateTeleportData(player: Player)
	return {
		teamOnePlayers = { { UserId = player.UserId, Name = player.Name } },
		teamTwoPlayers = { { UserId = 0, Name = "TestPlayer" } },
		queueType = 1,
		mapName = "TestMap",
		timestamp = os.time(),
	}
end

local function setupPlayer(player: Player)
	local teleportData

	if GlobalConfigs.TEST_MODE then
		print(`[Round] TEST_MODE — {player.Name} using template data (map: TestMap, 1v1)`)
		teleportData = buildTemplateTeleportData(player)
	else
		local joinData = player:GetJoinData()
		teleportData = joinData and joinData.TeleportData

		if not teleportData then
			warn(`[Round] No teleport data for {player.Name}`)
			return
		end

		local ok, err = TeleportDataValidator.validate(teleportData)
		if not ok then
			warn(`[Round] Invalid teleport data for {player.Name}: {err}`)
			return
		end
	end

	if not roundSystem then
		local expected = #teleportData.teamOnePlayers + #teleportData.teamTwoPlayers
		print(`[Round] Creating RoundSystem — map: {teleportData.mapName}, expecting {expected} player(s)`)
		roundSystem = RoundService.new(teleportData)
	end

	roundSystem:RegisterPlayer(player)

	player.CharacterAdded:Connect(function(character)
		if roundSystem:GetState() == Configs.GAME_STATES.WaitingForPlayers then
			local rootPart = character:WaitForChild("HumanoidRootPart", Configs.CHARACTER_LOAD_TIMEOUT)
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

	player:LoadCharacter()
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	if roundSystem then
		roundSystem:UnregisterPlayer(player)
	end
end)
