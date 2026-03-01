local Players = game:GetService("Players")
local DataService = require(script.Parent)


Players.PlayerAdded:Connect(function(player)
    DataService.OnPlayerAdded(player)
end)

Players.PlayerRemoving:Connect(function(player)
    DataService.OnPlayerRemoving(player)
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        DataService.OnPlayerRemoving(player)
    end
end)