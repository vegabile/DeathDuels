local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.KnifeSpeedBoost

local KnifeSpeedBoost = {}

KnifeSpeedBoost.name = "knifespeedboost"
KnifeSpeedBoost.cooldown = cfg.cooldown

function KnifeSpeedBoost.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function KnifeSpeedBoost:Execute(player: Player, _payload: any): boolean
	player:SetAttribute("KnifeCooldownMult", cfg.knifeCooldownMult)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("KnifeCooldownMult", nil)
	end)

	return true
end

return KnifeSpeedBoost
