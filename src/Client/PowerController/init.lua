local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local PowerController = {}

local effectHandlers: { [string]: (envelope: any) -> () } = {}

function PowerController.registerEffect(effectType: string, handler: (envelope: any) -> ())
	if effectHandlers[effectType] then
		warn(`[PowerController] Duplicate effect registration: {effectType}`)
		return
	end
	effectHandlers[effectType] = handler
end

function PowerController.start()
	NetworkRouter:Listen("PowerBroadcast", function(envelope)
		if type(envelope) ~= "table" then
			warn(`[PowerController] Non-table broadcast envelope`)
			return
		end
		if type(envelope.effectType) ~= "string" then
			warn(`[PowerController] Missing/invalid effectType`)
			return
		end
		local handler = effectHandlers[envelope.effectType]
		if not handler then
			warn(`[PowerController] Unknown effectType: {envelope.effectType}`)
			return
		end
		handler(envelope)
	end)
end

return PowerController
