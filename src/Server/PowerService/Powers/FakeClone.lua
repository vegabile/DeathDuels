local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local RoundScope = require(script.Parent.Parent.RoundScope)
local cfg = Configs.POWERS.FakeClone

local FakeClone = {}

FakeClone.name = "fakeclone"
FakeClone.cooldown = cfg.cooldown

function FakeClone.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function FakeClone:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[FakeClone] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[FakeClone] No HRP for {player.Name}`); return end

	local clone = char:Clone()

	
	for _, desc in clone:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	
	local cloneHum = clone:FindFirstChildOfClass("Humanoid")
	if cloneHum then
		cloneHum.NameDisplayDistance = 0
		cloneHum.HealthDisplayDistance = 0
	end

	clone.Parent = workspace
	local offsetCFrame = hrp.CFrame * CFrame.new(cfg.spawnOffset, 0, 0)
	if clone.PrimaryPart then
		clone:PivotTo(offsetCFrame)
	end

	RoundScope.Register(clone)
	Debris:AddItem(clone, cfg.durationSec)
end

return FakeClone
