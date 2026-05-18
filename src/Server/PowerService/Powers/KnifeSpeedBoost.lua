local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.KnifeSpeedBoost

local KnifeSpeedBoost = {}

KnifeSpeedBoost.name = "knifespeedboost"
KnifeSpeedBoost.cooldown = cfg.cooldown

function KnifeSpeedBoost.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function KnifeSpeedBoost:Execute(player: Player, _payload: any)
	EffectUtil.TemporaryAttribute(player, "KnifeCooldownMult", cfg.knifeCooldownMult, cfg.durationSec)
end

return KnifeSpeedBoost
