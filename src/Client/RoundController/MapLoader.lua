local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Configs = require(ReplicatedStorage.Round.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local MapLoader = {}

local localPlayer = Players.LocalPlayer
local started = false

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
			local ok, err = pcall(function()
				NetworkRouter:Call(Configs.MAP_READY_REMOTE, mapName)
			end)
			if not ok then
				warn(`[MapLoader] failed to send {Configs.MAP_READY_REMOTE}: {err}`)
			end
		end

		task.delay(Configs.MAP_LOAD_TIMEOUT, fireReady)

		local deadline = os.clock() + Configs.MAP_LOAD_TIMEOUT
		local root = waitForAnchoredRoot(deadline)
		if root then
			local streamOk, streamErr = pcall(function()
				localPlayer:RequestStreamAroundAsync(root.Position, math.max(0, deadline - os.clock()))
			end)
			if not streamOk then
				warn(`[MapLoader] RequestStreamAroundAsync failed: {streamErr}`)
			end
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
