local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.ShieldPulse

local ShieldPulse = {}

ShieldPulse.name = "shieldpulse"
ShieldPulse.cooldown = cfg.cooldown

function ShieldPulse.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function ShieldPulse:Execute(player: Player, _payload: any)
	EffectUtil.TemporaryAttribute(player, "ShieldActive", true, cfg.durationSec)
end

return ShieldPulse
