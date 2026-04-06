local Configs = require(script.Parent.Configs)

local validActionSet = {}
for _, name in Configs.ValidActions do
	validActionSet[name] = true
end

local PayloadValidator = {}

function PayloadValidator.validate(payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "Payload is not a table"
	end

	if type(payload.desiredAction) ~= "string" then
		return false, "desiredAction is not a string"
	end

	if not validActionSet[payload.desiredAction] then
		return false, `Unknown action: {payload.desiredAction}`
	end

	if type(payload.sequenceId) ~= "number" then
		return false, "sequenceId is not a number"
	end

	if payload.sequenceId < 1 or math.floor(payload.sequenceId) ~= payload.sequenceId then
		return false, "sequenceId must be a positive integer"
	end

	if payload.directionVector ~= nil then
		if typeof(payload.directionVector) ~= "Vector3" then
			return false, "directionVector is not a Vector3"
		end
		local mag = payload.directionVector.Magnitude
		if mag < 0.1 or mag > Configs.MaxDirectionMagnitude then
			return false, `directionVector magnitude out of range: {mag}`
		end
	end

	return true, nil
end

function PayloadValidator.normalizeDirection(directionVector: Vector3): Vector3
	return directionVector.Unit
end

return PayloadValidator
