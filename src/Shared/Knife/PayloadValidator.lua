local Configs = require(script.Parent.Configs)

local validActionSet = {}
for _, name in Configs.ValidActions do
	validActionSet[name] = true
end

local function debugLine(message: string)
	print("[KNIFE] [PayloadValidator] " .. message)
end

local PayloadValidator = {}

function PayloadValidator.validate(payload: any): (boolean, string?)
	debugLine("validate called")
	if type(payload) ~= "table" then
		debugLine("invalid payload type: " .. typeof(payload))
		return false, "Payload is not a table"
	end

	if type(payload.desiredAction) ~= "string" then
		debugLine("invalid desiredAction type: " .. typeof(payload.desiredAction))
		return false, "desiredAction is not a string"
	end

	if not validActionSet[payload.desiredAction] then
		debugLine("invalid action: " .. tostring(payload.desiredAction))
		return false, `Unknown action: {payload.desiredAction}`
	end

	if type(payload.sequenceId) ~= "number" then
		debugLine("invalid sequenceId type: " .. typeof(payload.sequenceId))
		return false, "sequenceId is not a number"
	end

	if payload.sequenceId < 1 or math.floor(payload.sequenceId) ~= payload.sequenceId then
		debugLine("invalid sequenceId value: " .. tostring(payload.sequenceId))
		return false, "sequenceId must be a positive integer"
	end

	if payload.directionVector ~= nil then
		if typeof(payload.directionVector) ~= "Vector3" then
			debugLine("invalid direction type: " .. typeof(payload.directionVector))
			return false, "directionVector is not a Vector3"
		end
		local mag = payload.directionVector.Magnitude
		if mag < 0.1 or mag > Configs.MaxDirectionMagnitude then
			debugLine("direction out of range: " .. tostring(mag))
			return false, `directionVector magnitude out of range: {mag}`
		end
	end

	debugLine(`payload valid action={payload.desiredAction} seq={payload.sequenceId} hasDir={payload.directionVector ~= nil}`)

	return true, nil
end

function PayloadValidator.normalizeDirection(directionVector: Vector3): Vector3
	debugLine(`normalizeDirection input={directionVector}`)
	return directionVector.Unit
end

return PayloadValidator
