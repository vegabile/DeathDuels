local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local EffectUtil = require(script.Parent.Parent.EffectUtil)
local cfg = Configs.POWERS.Launch

local Launch = {}

Launch.name = "launch"
Launch.cooldown = cfg.cooldown

function Launch.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Launch:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Launch] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Launch] No Humanoid for {player.Name}`); return end

	EffectUtil.TemporaryProperty(player, hum, "JumpPower", hum.JumpPower * cfg.jumpPowerMult, cfg.durationSec)
	hum.Jump = true   
end

return Launch
