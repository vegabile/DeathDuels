local Debris = game:GetService("Debris")

local PowerController = require(script.Parent.Parent)

local function apply(envelope: any)
	if typeof(envelope.targetCharacter) ~= "Instance" or not envelope.targetCharacter:IsA("Model") then
		warn(`[PowerController.Reveal] Invalid targetCharacter`)
		return
	end
	if envelope.targetCharacter.Parent == nil then
		warn(`[PowerController.Reveal] Target character is not parented`)
		return
	end
	if type(envelope.durationSec) ~= "number" or envelope.durationSec <= 0 then
		warn(`[PowerController.Reveal] Invalid durationSec`)
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "RevealHighlight"
	highlight.Adornee = envelope.targetCharacter
	highlight.FillColor = Color3.new(1, 0.2, 0.2)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = workspace
	Debris:AddItem(highlight, envelope.durationSec)
end

PowerController.registerEffect("Reveal", apply)

return apply
