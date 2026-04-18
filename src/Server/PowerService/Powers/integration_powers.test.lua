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

--// ─── Case: Sprint ────────────────────────────────────────────────────────

do
	freshSession()
	local SprintPower = require(ServerScriptService.PowerService.Powers.Sprint)
	local registry = makeRegistry(SprintPower)
	local char = buildCharacter("SprintChar")
	local player = mockPlayer({ name = "Sprinter", character = char })
	local svc = PowerService.new(player, { Power = "sprint" }, registry)

	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseSpeed = hum.WalkSpeed
	local r = svc:Activate("sprint", {})
	check("Sprint.1 accepted", r.success == true)
	check("Sprint.2 WalkSpeed elevated mid-duration", hum.WalkSpeed > baseSpeed + 0.01)

	task.wait(2.1)   --// duration + epsilon
	check("Sprint.3 WalkSpeed restored after duration", math.abs(hum.WalkSpeed - baseSpeed) < 0.01)

	destroyCharacter(char)
end

--// ─── Case: Launch ────────────────────────────────────────────────────────

do
	freshSession()
	local LaunchPower = require(ServerScriptService.PowerService.Powers.Launch)
	local registry = makeRegistry(LaunchPower)
	local char = buildCharacter("LaunchChar")
	local player = mockPlayer({ name = "Launcher", character = char })
	local svc = PowerService.new(player, { Power = "launch" }, registry)

	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseJump = hum.JumpPower
	local r = svc:Activate("launch", {})
	check("Launch.1 accepted", r.success == true)
	check("Launch.2 JumpPower elevated mid-duration", hum.JumpPower > baseJump + 0.01)

	task.wait(3.1)
	check("Launch.3 JumpPower restored after duration", math.abs(hum.JumpPower - baseJump) < 0.01)

	destroyCharacter(char)
end

--// ─── Case: QuickDraw ─────────────────────────────────────────────────────

do
	freshSession()
	local QDPower = require(ServerScriptService.PowerService.Powers.QuickDraw)
	local registry = makeRegistry(QDPower)
	local char = buildCharacter("QDChar")
	local player = mockPlayer({ name = "Drawer", character = char })
	local svc = PowerService.new(player, { Power = "quickdraw" }, registry)

	local r = svc:Activate("quickdraw", {})
	check("QuickDraw.1 accepted", r.success == true)
	check("QuickDraw.2 KnifeCooldownMult set mid-duration", player:GetAttribute("KnifeCooldownMult") == 0.5)
	check("QuickDraw.3 GunCooldownMult set mid-duration", player:GetAttribute("GunCooldownMult") == 0.5)

	task.wait(5.1)
	check("QuickDraw.4 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)
	check("QuickDraw.5 GunCooldownMult cleared", player:GetAttribute("GunCooldownMult") == nil)

	destroyCharacter(char)
end

--// ─── Case: KnifeSpeedBoost ───────────────────────────────────────────────

do
	freshSession()
	local KSBPower = require(ServerScriptService.PowerService.Powers.KnifeSpeedBoost)
	local registry = makeRegistry(KSBPower)
	local char = buildCharacter("KSBChar")
	local player = mockPlayer({ name = "KnifeBoost", character = char })
	local svc = PowerService.new(player, { Power = "knifespeedboost" }, registry)

	local r = svc:Activate("knifespeedboost", {})
	check("KnifeSpeedBoost.1 accepted", r.success == true)
	check("KnifeSpeedBoost.2 KnifeCooldownMult set", player:GetAttribute("KnifeCooldownMult") == 0.74)
	check("KnifeSpeedBoost.3 GunCooldownMult NOT set", player:GetAttribute("GunCooldownMult") == nil)

	task.wait(5.1)
	check("KnifeSpeedBoost.4 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)

	destroyCharacter(char)
end

print(`\n{passed} passed, {failed} failed`)
