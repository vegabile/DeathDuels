local Players = game:GetService("Players")

local RoundService = require(script.Parent)
local TeleportDataValidator = require(script.Parent.TeleportDataValidator)

local roundSystem = nil

local function setupPlayer(player: Player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if not teleportData then
		warn(`[RoundService] No teleport data for {player.Name}`)
		return
	end

	local ok, err = TeleportDataValidator.validate(teleportData)
	if not ok then
		warn(`[RoundService] Invalid teleport data for {player.Name}: {err}`)
		return
	end

	if not roundSystem then
		roundSystem = RoundService.new(teleportData)
	end

	roundSystem:RegisterPlayer(player)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			roundSystem:OnPlayerDied(player)
		end)
	end)
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
