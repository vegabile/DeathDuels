local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ClientEventBus = require(script.Parent.ClientEventBus)
local GameStateUIBinder = require(script.GameStateUIBinder)

local RoundController = {}
local initialized = false
local lastRoundState: string? = nil

local function publishSnapshot(snapshot: any)
	ClientEventBus:Fire("RoundUpdate", snapshot)
	if type(snapshot) ~= "table" or type(snapshot.state) ~= "string" then
		return
	end
	if snapshot.state == lastRoundState then
		return
	end
	lastRoundState = snapshot.state
	ClientEventBus:FireSticky("RoundStateChanged", snapshot.state)
end

function RoundController.Init()
	if initialized then
		return
	end
	initialized = true

	GameStateUIBinder.Init()

	NetworkRouter:Listen("RoundUpdate", function(snapshot)
		publishSnapshot(snapshot)
	end)

	task.spawn(function()
		local ok, snapshot = pcall(function()
			return NetworkRouter:Call("RoundGetSnapshot")
		end)
		if ok and type(snapshot) == "table" then
			publishSnapshot(snapshot)
		end
	end)
end

return RoundController
