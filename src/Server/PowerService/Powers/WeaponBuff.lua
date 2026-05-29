local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.WeaponBuff

local WeaponBuff = {}

WeaponBuff.name = "weaponbuff"
WeaponBuff.cooldown = cfg.cooldown

function WeaponBuff.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function WeaponBuff:Execute(player: Player, _payload: any): boolean
	player:SetAttribute("KnifeCooldownMult", cfg.knifeCooldownMult)
	player:SetAttribute("GunCooldownMult", cfg.gunCooldownMult)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("KnifeCooldownMult", nil)
		player:SetAttribute("GunCooldownMult", nil)
	end)

	return true
end

return WeaponBuff
