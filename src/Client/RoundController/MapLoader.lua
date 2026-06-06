-- MapLoader (client)
--
-- Ensures the area around the local player's combat spawn is fully streamed in
-- before the server releases them into RoundActive, so nobody is unfrozen into a
-- half-loaded map. This assumes StreamingEnabled is ON: the client never holds
-- the whole map, so we stream the spawn region with RequestStreamAroundAsync
-- (which yields until those parts are present) rather than counting descendants.
--
-- We key off the local character: the server positions AND anchors it at the
-- combat spawn during PreparingPlayers (RoundOrchestrator.exitSkippedOrPosition,
-- hrp.Anchored = true), so an anchored root is the deterministic "I'm at my
-- spawn" signal — no server-sent spawn coordinates needed.
--
-- Gating is first-round-only: we report MapReady once per client (the server
-- records the fact and never clears it), matching READINESS_GRACE_FIRST_ROUND.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Configs = require(ReplicatedStorage.Round.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local MapLoader = {}

local localPlayer = Players.LocalPlayer
local started = false

-- Waits (until the deadline) for our character's root part to be anchored, which
-- the server only does once it has placed us at our combat spawn. Falls back to
-- whatever root we currently have so we can still stream best-effort.
local function waitForAnchoredRoot(deadline: number): BasePart?
	while os.clock() < deadline do
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and root.Anchored then
			return root
		end
		task.wait()
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Idempotent: safe to call on every PreparingPlayers snapshot; only acts once.
function MapLoader.ensureReady(mapName: string?)
	if started then
		return
	end
	started = true

	task.spawn(function()
		local fired = false
		local function fireReady()
			if fired then
				return
			end
			fired = true
			NetworkRouter:Call(Configs.MAP_READY_REMOTE, mapName)
		end

		-- Hard cap: report ready on an independent thread even if streaming or
		-- asset preload below stalls, so we never miss the server's readiness
		-- grace and get wrongly Skipped.
		task.delay(Configs.MAP_LOAD_TIMEOUT, fireReady)

		local deadline = os.clock() + Configs.MAP_LOAD_TIMEOUT
		local root = waitForAnchoredRoot(deadline)
		if root then
			-- Stream the world around our spawn and yield until it's present.
			-- The timeout arg bounds the yield; pcall guards the case where
			-- StreamingEnabled is off (call no-ops / errors) so we never hang.
			pcall(function()
				workspace:RequestStreamAroundAsync(root.Position, math.max(0, deadline - os.clock()))
			end)
			-- Decode the streamed-in map assets (textures/meshes/sounds).
			local mapModel = if type(mapName) == "string" then workspace:FindFirstChild(mapName) else nil
			if mapModel then
				pcall(function()
					ContentProvider:PreloadAsync({ mapModel })
				end)
			end
		else
			warn("[MapLoader] no character root to stream around; reporting ready best-effort")
		end

		fireReady()
	end)
end

return MapLoader
