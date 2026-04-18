local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.SmokeScreen

local SmokeScreen = {}

SmokeScreen.name = "smokescreen"
SmokeScreen.cooldown = cfg.cooldown

function SmokeScreen.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function SmokeScreen:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[SmokeScreen] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[SmokeScreen] No HRP for {player.Name}`); return end

	local origin = hrp.Position + hrp.CFrame.LookVector * cfg.spawnForward

	local part = Instance.new("Part")
	part.Name = "SmokeScreenCloud"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = origin
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(2, 4)
	emitter.Size = NumberSequence.new(8)
	emitter.Color = ColorSequence.new(Color3.new(0.1, 0.1, 0.1))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1,   1),
	})
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part

	Debris:AddItem(part, cfg.durationSec)
end

return SmokeScreen
