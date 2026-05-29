local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.ShieldPulse

local ShieldPulse = {}

ShieldPulse.name = "shieldpulse"
ShieldPulse.cooldown = cfg.cooldown

function ShieldPulse.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function ShieldPulse:Execute(player: Player, _payload: any): boolean
	player:SetAttribute("ShieldActive", true)

	task.delay(cfg.durationSec, function()
		--// Idempotent: if an attacker already consumed the flag, this is a no-op.
		if player:GetAttribute("ShieldActive") then
			player:SetAttribute("ShieldActive", nil)
		end
	end)

	return true
end

return ShieldPulse
