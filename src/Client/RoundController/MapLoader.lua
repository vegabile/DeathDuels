-- MapLoader (client)
--
-- Ensures the local player's copy of the match map is fully present before the
-- server releases them into RoundActive. Two things have to happen on the client:
--
--   1. Replication — the map model the server parented to workspace has to stream
--      down part-by-part. PreloadAsync does NOT do this; it only loads the assets
--      (textures/meshes/sounds) referenced by instances that already exist. So we
--      first wait for the model's descendant count to reach the server-reported
--      total (falling back to "the count stopped growing" if no total is known).
--   2. Asset preloading — once the instances exist, ContentProvider:PreloadAsync
--      yields until their textures/meshes/sounds are decoded and ready.
--
-- When both are done (or we hit a hard timeout) we fire MAP_READY_REMOTE so the
-- server records the player's "MapReady" readiness fact.
--
-- NOTE: this assumes the map replicates in full (StreamingEnabled off, which is
-- the case here). With StreamingEnabled the descendant count would not be a
-- reliable signal and you'd want RequestStreamAroundAsync around the spawn instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Configs = require(ReplicatedStorage.Round.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local MapLoader = {}

local readyMap: string? = nil
local loadingMap: string? = nil

-- Waits until the map looks fully replicated. Returns true if we're confident it
-- is, false if we bailed on the deadline before reaching the expected count.
local function waitForReplication(model: Instance, expectedCount: number?, deadline: number): boolean
	local lastCount = -1
	local stableFrames = 0
	while os.clock() < deadline do
		local count = #model:GetDescendants()
		if expectedCount and count >= expectedCount then
			return true
		end
		if count == lastCount then
			stableFrames += 1
			-- No new instances are arriving. If we have no count target, treat
			-- the map as fully replicated; if we do have one and still haven't
			-- reached it, keep waiting until the deadline.
			if stableFrames >= Configs.MAP_STABLE_FRAMES and not expectedCount then
				return true
			end
		else
			stableFrames = 0
			lastCount = count
		end
		task.wait(Configs.MAP_POLL_INTERVAL)
	end
	return false
end

-- Idempotent per map name: safe to call on every round snapshot.
function MapLoader.ensureLoaded(mapName: string?, expectedPartCount: number?)
	if type(mapName) ~= "string" or mapName == "" then
		return
	end
	if readyMap == mapName or loadingMap == mapName then
		return
	end
	loadingMap = mapName

	task.spawn(function()
		local deadline = os.clock() + Configs.MAP_LOAD_TIMEOUT
		local model = workspace:FindFirstChild(mapName)
		if not model then
			model = workspace:WaitForChild(mapName, math.max(0, deadline - os.clock()))
		end

		local fullyReplicated = false
		if model then
			fullyReplicated = waitForReplication(model, expectedPartCount, deadline)
			-- Yields until the map's textures/meshes/sounds are loaded.
			pcall(function()
				ContentProvider:PreloadAsync({ model })
			end)
		end

		if not model then
			warn(`[MapLoader] map "{mapName}" never replicated within {Configs.MAP_LOAD_TIMEOUT}s; reporting ready best-effort`)
		elseif not fullyReplicated then
			warn(`[MapLoader] map "{mapName}" not confirmed fully replicated before timeout; reporting ready best-effort`)
		end

		readyMap = mapName
		loadingMap = nil
		NetworkRouter:Call(Configs.MAP_READY_REMOTE, mapName)
	end)
end

return MapLoader
