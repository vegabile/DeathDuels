local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Launch

local Launch = {}

Launch.name = "launch"
Launch.cooldown = cfg.cooldown

function Launch.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Launch:Execute(player: Player, _payload: any): boolean
	local char = player.Character
	if not char then warn(`[Launch] No character for {player.Name}`); return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Launch] No Humanoid for {player.Name}`); return false end

	local baseJump = hum.JumpPower
	hum.JumpPower = baseJump * cfg.jumpPowerMult
	hum.Jump = true   --// trigger the boosted jump immediately

	task.delay(cfg.durationSec, function()
		if hum and hum.Parent then
			hum.JumpPower = baseJump
		end
	end)

	return true
end

return Launch
