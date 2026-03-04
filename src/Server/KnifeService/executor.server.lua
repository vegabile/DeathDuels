local Players = game:GetService("Players")
local KnifeService = require(script.Parent)

Players.PlayerAdded:Connect(function(player)
	KnifeService.OnPlayerAdded(player)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			KnifeService.OnPlayerDied(player)
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	KnifeService.OnPlayerRemoving(player)
end)
