local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.QuickDraw

local QuickDraw = {}

QuickDraw.name = "quickdraw"
QuickDraw.cooldown = cfg.cooldown

function QuickDraw.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function QuickDraw:Execute(player: Player, _payload: any)
	player:SetAttribute("KnifeCooldownMult", cfg.cooldownMult)
	player:SetAttribute("GunCooldownMult", cfg.cooldownMult)

	task.delay(cfg.durationSec, function()
		player:SetAttribute("KnifeCooldownMult", nil)
		player:SetAttribute("GunCooldownMult", nil)
	end)
end

return QuickDraw
