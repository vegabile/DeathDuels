local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.QuickDraw

local QuickDraw = {}

QuickDraw.name = "quickdraw"
QuickDraw.cooldown = cfg.cooldown

function QuickDraw.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function QuickDraw:Execute(player: Player, _payload: any)
	EffectUtil.TemporaryAttribute(player, "KnifeCooldownMult", cfg.cooldownMult, cfg.durationSec)
	EffectUtil.TemporaryAttribute(player, "GunCooldownMult", cfg.cooldownMult, cfg.durationSec)
end

return QuickDraw
