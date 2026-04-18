--// Integration suite for concrete Powers. Run via mcp__robloxstudio__execute_luau.
--// Each case wires a single power into an injected registry, activates it, and
--// asserts the mid-duration + post-duration observable state.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PowerService = require(ServerScriptService.PowerService)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local passed, failed = 0, 0
local function check(label: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
		print(`PASS: {label}`)
	else
		failed += 1
		print(`FAIL: {label}{if detail then " — " .. tostring(detail) else ""}`)
	end
end

--// ─── Fixtures ────────────────────────────────────────────────────────────

local function setRoundActive() ServerEventBus:Fire("RoundStateChanged", "RoundActive") end

--// Builds a real-Instance character (Model with HRP, Head, Humanoid, Decal).
--// Caller is responsible for destroying via destroyCharacter.
local function buildCharacter(name: string): Model
	local model = Instance.new("Model")
	model.Name = name

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.Transparency = 0
	hrp.CFrame = CFrame.new(0, 10, 0)
	hrp.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Anchored = true
	head.Transparency = 0
	head.CFrame = CFrame.new(0, 12, 0)
	head.Parent = model

	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Parent = head

	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.Health = 100
	hum.Parent = model

	model.PrimaryPart = hrp
	model.Parent = workspace
	return model
end

local function destroyCharacter(model: Model?)
	if model and model.Parent then model:Destroy() end
end

--// Mock Player table with the full surface PowerService + powers read.
local function mockPlayer(opts)
	opts = opts or {}
	local player
	player = {
		Name = opts.name or "Tester",
		UserId = opts.userId or math.random(100000, 999999),
		Character = opts.character,
		_attrs = {},
	}
	function player:SetAttribute(n, v) self._attrs[n] = v end
	function player:GetAttribute(n) return self._attrs[n] end
	function player:IsDescendantOf(container)
		if opts.inGame == false then return false end
		return container == Players
	end
	return player
end

local function makeRegistry(power)
	return {
		getPower = function(name) if name == power.name then return power end return nil end,
	}
end

local function freshSession()
	PowerService._reset()
	setRoundActive()
end

--// ─── Per-power cases will be appended below as each power lands ──────────
--// (Tasks 8–20 each add one case.)

print(`\n{passed} passed, {failed} failed`)
