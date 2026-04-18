local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
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

	local baseSpeed = hum.WalkSpeed
	hum.WalkSpeed = baseSpeed * cfg.speedMult
	player:SetAttribute("KnifeCooldownMult", cfg.cooldownMult)
	player:SetAttribute("GunCooldownMult", cfg.cooldownMult)

	task.delay(cfg.durationSec, function()
		if hum and hum.Parent then
			hum.WalkSpeed = baseSpeed
		end
		player:SetAttribute("KnifeCooldownMult", nil)
		player:SetAttribute("GunCooldownMult", nil)
	end)
end

return Adrenaline
