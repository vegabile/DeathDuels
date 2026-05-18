local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.Sprint

local Sprint = {}

Sprint.name = "sprint"
Sprint.cooldown = cfg.cooldown

function Sprint.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Sprint:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Sprint] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Sprint] No Humanoid for {player.Name}`); return end

	EffectUtil.TemporaryProperty(player, hum, "WalkSpeed", hum.WalkSpeed * cfg.speedMult, cfg.durationSec)
end

return Sprint
