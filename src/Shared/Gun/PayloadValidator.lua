local Configs = require(script.Parent.Configs)

local validActionSet = {}
for _, name in Configs.ValidActions do
	validActionSet[name] = true
end


local REQUIRES_REST_ORIGIN: { [string]: boolean } = {
	Shoot = true,
}

local REQUIRES_DIRECTION: { [string]: boolean } = {
	Shoot = true,
}

local PayloadValidator = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isNonNegativeInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 0 and math.floor(value) == value
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 1 and math.floor(value) == value
end

local function isFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

function PayloadValidator.sanitizeSequenceId(payload: any): number
	if type(payload) ~= "table" then
		return 0
	end
	local raw = payload.sequenceId
	if isNonNegativeInteger(raw) then
		return raw
	end
	return 0
end

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

	if not isFiniteNumber(payload.sequenceId) then
		return false, "sequenceId is not a number"
	end

	if not isPositiveInteger(payload.sequenceId) then
		return false, "sequenceId must be a positive integer"
	end

	if REQUIRES_DIRECTION[payload.desiredAction] and typeof(payload.directionVector) ~= "Vector3" then
		return false, "directionVector is required and must be a Vector3"
	end

	if payload.directionVector ~= nil then
		if not isFiniteVector3(payload.directionVector) then
			return false, "directionVector is not a Vector3"
		end
		local mag = payload.directionVector.Magnitude
		if not isFiniteNumber(mag) or mag < 0.1 or mag > Configs.MaxDirectionMagnitude then
			return false, `directionVector magnitude out of range: {mag}`
		end
	end

	if REQUIRES_REST_ORIGIN[payload.desiredAction] then
		if not isFiniteVector3(payload.restOrigin) then
			return false, "restOrigin is required and must be a Vector3"
		end
	elseif payload.restOrigin ~= nil and not isFiniteVector3(payload.restOrigin) then
		return false, "restOrigin must be a Vector3 when present"
	end

	return true, nil
end

function PayloadValidator.normalizeDirection(directionVector: Vector3): Vector3
	return directionVector.Unit
end

return PayloadValidator
