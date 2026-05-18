local Players = game:GetService("Players")
local GunService = require(script.Parent)

local handled = setmetatable({}, { __mode = "k" }) :: { [Player]: boolean }

local function setupPlayer(player)
	if handled[player] then
		warn(`[GunService.executor] setup skipped for {player.Name}: already handled`)
		return
	end
	handled[player] = true

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
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	GunService.OnPlayerRemoving(player)
end)
