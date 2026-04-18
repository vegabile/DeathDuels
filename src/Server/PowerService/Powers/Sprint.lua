local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Sprint

local Sprint = {}

Sprint.name = "sprint"
Sprint.cooldown = cfg.cooldown

function Sprint.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Sprint:Execute(player: Player, _payload: any): boolean
	local char = player.Character
	if not char then warn(`[Sprint] No character for {player.Name}`); return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Sprint] No Humanoid for {player.Name}`); return false end

	local baseSpeed = hum.WalkSpeed
	hum.WalkSpeed = baseSpeed * cfg.speedMult

	task.delay(cfg.durationSec, function()
		if hum and hum.Parent then
			hum.WalkSpeed = baseSpeed
		end
	end)

	return true
end

return Sprint
