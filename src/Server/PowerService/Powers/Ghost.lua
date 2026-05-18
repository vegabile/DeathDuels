local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local Configs = require(script.Parent.Parent.Configs)
local RoundScope = require(script.Parent.Parent.RoundScope)
local cfg = Configs.POWERS.Ghost

local Ghost = {}

Ghost.name = "ghost"
Ghost.cooldown = cfg.cooldown

function Ghost.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Ghost:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Ghost] No character for {player.Name}`); return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then warn(`[Ghost] No Humanoid for {player.Name}`); return end

	local originals: { [Instance]: number } = {}
	for _, desc in char:GetDescendants() do
		if desc:IsA("BasePart") then
			originals[desc] = desc.Transparency
			desc.Transparency = 1
		elseif desc:IsA("Decal") then
			originals[desc] = desc.Transparency
			desc.Transparency = 1
		end
	end
	local baseNameDist = hum.NameDisplayDistance
	local baseHealthDist = hum.HealthDisplayDistance
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0

	local function revert()
		if next(originals) == nil then return end   
		for inst, t in originals do
			if inst and inst.Parent then inst.Transparency = t end
		end
		originals = {}
		if hum and hum.Parent then
			hum.NameDisplayDistance = baseNameDist
			hum.HealthDisplayDistance = baseHealthDist
		end
	end

	local unregister = RoundScope.RegisterCleanup(revert)
	hum.Died:Connect(unregister)
	task.delay(cfg.durationSec, unregister)
end

return Ghost
