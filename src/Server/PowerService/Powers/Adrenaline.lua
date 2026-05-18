local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.Adrenaline

local Adrenaline = {}

Adrenaline.name = "adrenaline"
Adrenaline.cooldown = cfg.cooldown

function Adrenaline.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Adrenaline:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Adrenaline] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Adrenaline] No Humanoid for {player.Name}`); return end

	EffectUtil.TemporaryProperty(player, hum, "WalkSpeed", hum.WalkSpeed * cfg.speedMult, cfg.durationSec)
	EffectUtil.TemporaryAttribute(player, "KnifeCooldownMult", cfg.cooldownMult, cfg.durationSec)
	EffectUtil.TemporaryAttribute(player, "GunCooldownMult", cfg.cooldownMult, cfg.durationSec)
end

return Adrenaline
