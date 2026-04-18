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

--// ─── Case: WeaponBuff ────────────────────────────────────────────────────

do
	freshSession()
	local WBPower = require(ServerScriptService.PowerService.Powers.WeaponBuff)
	local registry = makeRegistry(WBPower)
	local char = buildCharacter("WBChar")
	local player = mockPlayer({ name = "WBTester", character = char })
	local svc = PowerService.new(player, { Power = "weaponbuff" }, registry)

	local r = svc:Activate("weaponbuff", {})
	check("WeaponBuff.1 accepted", r.success == true)
	check("WeaponBuff.2 KnifeCooldownMult set", player:GetAttribute("KnifeCooldownMult") == 0.74)
	check("WeaponBuff.3 GunCooldownMult set", player:GetAttribute("GunCooldownMult") == 0.69)

	task.wait(5.1)
	check("WeaponBuff.4 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)
	check("WeaponBuff.5 GunCooldownMult cleared", player:GetAttribute("GunCooldownMult") == nil)

	destroyCharacter(char)
end

--// ─── Case: Adrenaline ────────────────────────────────────────────────────

do
	freshSession()
	local AdrPower = require(ServerScriptService.PowerService.Powers.Adrenaline)
	local registry = makeRegistry(AdrPower)
	local char = buildCharacter("AdrChar")
	local player = mockPlayer({ name = "Adrenalized", character = char })
	local svc = PowerService.new(player, { Power = "adrenaline" }, registry)

	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseSpeed = hum.WalkSpeed
	local r = svc:Activate("adrenaline", {})
	check("Adrenaline.1 accepted", r.success == true)
	check("Adrenaline.2 WalkSpeed elevated", hum.WalkSpeed > baseSpeed + 0.01)
	check("Adrenaline.3 KnifeCooldownMult set", player:GetAttribute("KnifeCooldownMult") == 0.7)
	check("Adrenaline.4 GunCooldownMult set", player:GetAttribute("GunCooldownMult") == 0.7)

	task.wait(5.1)
	check("Adrenaline.5 WalkSpeed restored", math.abs(hum.WalkSpeed - baseSpeed) < 0.01)
	check("Adrenaline.6 KnifeCooldownMult cleared", player:GetAttribute("KnifeCooldownMult") == nil)
	check("Adrenaline.7 GunCooldownMult cleared", player:GetAttribute("GunCooldownMult") == nil)

	destroyCharacter(char)
end

--// ─── Case: Dash ──────────────────────────────────────────────────────────

do
	freshSession()
	local DashPower = require(ServerScriptService.PowerService.Powers.Dash)
	local registry = makeRegistry(DashPower)
	local char = buildCharacter("DashChar")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	hrp.Anchored = false   --// LinearVelocity needs a dynamic HRP; gravity is fine since we destroy the char in <1s
	local player = mockPlayer({ name = "Dasher", character = char })
	local svc = PowerService.new(player, { Power = "dash" }, registry)

	local r = svc:Activate("dash", {})
	check("Dash.1 accepted", r.success == true)
	check("Dash.2 CombatDisabled set mid-duration", player:GetAttribute("CombatDisabled") == true)
	local lv = hrp:FindFirstChildOfClass("LinearVelocity")
	check("Dash.3 LinearVelocity exists under HRP mid-duration", lv ~= nil)

	task.wait(0.45)   --// duration + epsilon
	check("Dash.4 CombatDisabled cleared", player:GetAttribute("CombatDisabled") == nil)
	local lv2 = hrp:FindFirstChildOfClass("LinearVelocity")
	check("Dash.5 LinearVelocity removed after duration", lv2 == nil)

	destroyCharacter(char)
end

--// ─── Case: ShieldPulse ───────────────────────────────────────────────────

do
	freshSession()
	local ShieldPower = require(ServerScriptService.PowerService.Powers.ShieldPulse)
	local registry = makeRegistry(ShieldPower)
	local char = buildCharacter("ShieldChar")
	local player = mockPlayer({ name = "Shielded", character = char })
	local svc = PowerService.new(player, { Power = "shieldpulse" }, registry)

	local r = svc:Activate("shieldpulse", {})
	check("ShieldPulse.1 accepted", r.success == true)
	check("ShieldPulse.2 ShieldActive mid-duration", player:GetAttribute("ShieldActive") == true)

	task.wait(2.1)
	check("ShieldPulse.3 ShieldActive cleared after duration", player:GetAttribute("ShieldActive") == nil)

	destroyCharacter(char)
end

--// ─── Case: Ghost ─────────────────────────────────────────────────────────

do
	freshSession()
	local GhostPower = require(ServerScriptService.PowerService.Powers.Ghost)
	local registry = makeRegistry(GhostPower)
	local char = buildCharacter("GhostChar")
	local player = mockPlayer({ name = "Ghosted", character = char })
	local svc = PowerService.new(player, { Power = "ghost" }, registry)

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	local baseHrpT, baseHeadT = hrp.Transparency, head.Transparency

	local r = svc:Activate("ghost", {})
	check("Ghost.1 accepted", r.success == true)
	check("Ghost.2 HRP transparent mid-duration", hrp.Transparency == 1)
	check("Ghost.3 Head transparent mid-duration", head.Transparency == 1)

	task.wait(4.1)
	check("Ghost.4 HRP restored", math.abs(hrp.Transparency - baseHrpT) < 0.01)
	check("Ghost.5 Head restored", math.abs(head.Transparency - baseHeadT) < 0.01)

	destroyCharacter(char)
end


--// ─── Case: Reveal ────────────────────────────────────────────────────────

do
	freshSession()
	local RevealPower = require(ServerScriptService.PowerService.Powers.Reveal)
	local registry = makeRegistry(RevealPower)

	local activatorChar = buildCharacter("RevealActivator")
	local targetChar = buildCharacter("RevealTarget")
	local activator = mockPlayer({ name = "Activator", userId = 20001, character = activatorChar })
	local target = mockPlayer({ name = "Target", userId = 20002, character = targetChar })

	--// Reveal scans Players:GetPlayers() for enemies — our mocks aren't real Players,
	--// so stub the relevant globals.
	local origGetPlayers = Players.GetPlayers
	Players.GetPlayers = function() return { activator, target } end
	local origGetTeam = TeleportMetadataService.GetTeam
	TeleportMetadataService.GetTeam = function(player)
		if player == activator then return 1 end
		if player == target then return 2 end
		return nil
	end

	--// Capture NetworkRouter:Call invocations.
	local calls = {}
	local origCall = NetworkRouter.Call
	NetworkRouter.Call = function(self, name, plr, payload)
		table.insert(calls, { name = name, player = plr, payload = payload })
	end

	local svc = PowerService.new(activator, { Power = "reveal" }, registry)
	local r = svc:Activate("reveal", {})
	check("Reveal.1 accepted", r.success == true)
	check("Reveal.2 exactly one NetworkRouter:Call", #calls == 1)
	local c = calls[1]
	check("Reveal.3 remote = PowerBroadcast", c and c.name == "PowerBroadcast")
	check("Reveal.4 delivered to activator", c and c.player == activator)
	check("Reveal.5 effectType = Reveal", c and c.payload and c.payload.effectType == "Reveal")
	check("Reveal.6 targetCharacter = target's char", c and c.payload and c.payload.targetCharacter == targetChar)
	check("Reveal.7 durationSec = 4", c and c.payload and c.payload.durationSec == 4)

	NetworkRouter.Call = origCall
	Players.GetPlayers = origGetPlayers
	TeleportMetadataService.GetTeam = origGetTeam

	destroyCharacter(activatorChar)
	destroyCharacter(targetChar)
end


--// ─── Case: FakeClone ─────────────────────────────────────────────────────

do
	freshSession()
	local ClonePower = require(ServerScriptService.PowerService.Powers.FakeClone)
	local registry = makeRegistry(ClonePower)
	local char = buildCharacter("CloneChar")
	local player = mockPlayer({ name = "Cloner", character = char })
	local svc = PowerService.new(player, { Power = "fakeclone" }, registry)

	local preClones = #workspace:GetChildren()
	local r = svc:Activate("fakeclone", {})
	check("FakeClone.1 accepted", r.success == true)

	task.wait(0.1)
	local postClones = #workspace:GetChildren()
	check("FakeClone.2 new child parented to workspace", postClones == preClones + 1)

	local cloneModel
	for _, c in workspace:GetChildren() do
		if c:IsA("Model") and c.Name:match("^CloneChar") and c ~= char then
			cloneModel = c
			break
		end
	end
	check("FakeClone.3 clone is a Model", cloneModel ~= nil)

	task.wait(8.1)
	check("FakeClone.4 clone removed after duration",
		cloneModel == nil or cloneModel.Parent == nil)

	destroyCharacter(char)
end

print(`\n{passed} passed, {failed} failed`)
