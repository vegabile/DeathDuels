local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local KnifeService = require(script.Parent)

NetworkRouter:CreateRemoteEvent("KnifeThrowBroadcast")

local function setupPlayer(player)
	KnifeService.OnPlayerAdded(player)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			KnifeService.OnPlayerDied(player)
		end)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	KnifeService.OnPlayerRemoving(player)
end)
