local Players = game:GetService("Players")
local DataService = require(script.Parent)

local handled = setmetatable({}, { __mode = "k" }) :: { [Player]: boolean }

local function safeAdd(player: Player)
    if handled[player] then
        warn(`[DataService.executor] safeAdd skipped for {player.Name}: already handled`)
        return
    end
    handled[player] = true
    DataService:OnPlayerAdded(player)
end

Players.PlayerAdded:Connect(safeAdd)

Players.PlayerRemoving:Connect(function(player)
    DataService:OnPlayerRemoving(player)
end)

for _, player in Players:GetPlayers() do
    task.spawn(safeAdd, player)
end

game:BindToClose(function()
    for _, player in Players:GetPlayers() do
        DataService:OnPlayerRemoving(player)
    end
end)
