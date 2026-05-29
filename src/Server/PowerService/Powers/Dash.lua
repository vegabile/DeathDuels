local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Dash

local Dash = {}

Dash.name = "dash"
Dash.cooldown = cfg.cooldown

function Dash.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Dash:Execute(player: Player, _payload: any): boolean
	local char = player.Character
	if not char then warn(`[Dash] No character for {player.Name}`); return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[Dash] No HumanoidRootPart for {player.Name}`); return false end

	local direction = hrp.CFrame.LookVector

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = hrp

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DashVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	linearVelocity.VectorVelocity = direction * cfg.impulseSpeed
	linearVelocity.Parent = hrp

	player:SetAttribute("CombatDisabled", true)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("CombatDisabled", nil)
		if linearVelocity and linearVelocity.Parent then linearVelocity:Destroy() end
		if attachment and attachment.Parent then attachment:Destroy() end
	end)

	return true
end

return Dash
