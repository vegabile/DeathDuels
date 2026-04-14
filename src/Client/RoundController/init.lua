local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ClientEventBus = require(script.Parent.ClientEventBus)
local GameStateUIBinder = require(script.GameStateUIBinder)

local RoundController = {}
local initialized = false

function RoundController.Init()
	if initialized then
		return
	end
	initialized = true

	GameStateUIBinder.Init()

	NetworkRouter:Listen("RoundUpdate", function(snapshot)
		ClientEventBus:Fire("RoundUpdate", snapshot)
	end)

	task.spawn(function()
		local ok, snapshot = pcall(function()
			return NetworkRouter:Call("RoundGetSnapshot")
		end)
		if ok and type(snapshot) == "table" then
			ClientEventBus:Fire("RoundUpdate", snapshot)
		end
	end)
end

return RoundController
