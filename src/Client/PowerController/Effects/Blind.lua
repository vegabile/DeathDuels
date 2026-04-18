local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local PowerController = require(script.Parent.Parent)

local localPlayer = Players.LocalPlayer

local function apply(envelope: any)
	if type(envelope.durationSec) ~= "number" or envelope.durationSec <= 0 then
		warn(`[PowerController.Blind] Invalid durationSec`)
		return
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn(`[PowerController.Blind] No PlayerGui`)
		return
	end

	local template = playerGui:FindFirstChild("PowerOverlays")
	template = template and template:FindFirstChild("BlindOverlay")
	if not template then
		warn(`[PowerController.Blind] BlindOverlay template missing — expected at PlayerGui.PowerOverlays.BlindOverlay`)
		return
	end

	local gui = template:Clone()
	gui.Enabled = true
	gui.Parent = playerGui
	Debris:AddItem(gui, envelope.durationSec)
end

PowerController.registerEffect("Blind", apply)

return apply
