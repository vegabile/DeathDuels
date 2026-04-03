local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ClientEventBus = require(script.Parent.ClientEventBus)

local RoundController = {}

function RoundController.Init()
	NetworkRouter:Listen("RoundUpdate", function(snapshot)
		ClientEventBus:Fire("RoundUpdate", snapshot)
	end)
end

return RoundController
