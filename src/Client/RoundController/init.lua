local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Round.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ClientEventBus = require(script.Parent.ClientEventBus)
local GameStateUIBinder = require(script.GameStateUIBinder)
local MapLoader = require(script.MapLoader)

local RoundController = {}
local initialized = false
local lastRoundState: string? = nil

-- States in which there is no live map to preload (no match running yet, or the
-- match has ended and players are leaving).
local NON_MATCH_STATES = {
	[Configs.GAME_STATES.WaitingForPlayers] = true,
	[Configs.GAME_STATES.TeleportingOut] = true,
	[Configs.GAME_STATES.Aborted] = true,
}

local function publishSnapshot(snapshot: any)
	ClientEventBus:Fire("RoundUpdate", snapshot)
	if type(snapshot) ~= "table" or type(snapshot.state) ~= "string" then
		return
	end

	-- Once a match is underway, make sure the map is fully loaded locally and
	-- report readiness to the server. ensureLoaded is idempotent per map name.
	if type(snapshot.mapName) == "string" and not NON_MATCH_STATES[snapshot.state] then
		MapLoader.ensureLoaded(snapshot.mapName, snapshot.mapPartCount)
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
