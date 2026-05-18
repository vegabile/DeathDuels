local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.WeaponBuff

local WeaponBuff = {}

WeaponBuff.name = "weaponbuff"
WeaponBuff.cooldown = cfg.cooldown

function WeaponBuff.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function WeaponBuff:Execute(player: Player, _payload: any)
	EffectUtil.TemporaryAttribute(player, "KnifeCooldownMult", cfg.knifeCooldownMult, cfg.durationSec)
	EffectUtil.TemporaryAttribute(player, "GunCooldownMult", cfg.gunCooldownMult, cfg.durationSec)
end

return WeaponBuff
