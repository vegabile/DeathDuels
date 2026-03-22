local Players = game:GetService("Players")
local GunService = require(script.Parent)

local function setupPlayer(player)
	GunService.OnPlayerAdded(player)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			GunService.OnPlayerDied(player)
		end)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	GunService.OnPlayerRemoving(player)
end)
