local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local Types = require(ReplicatedStorage.Power.Types)

type PowerFailReason = Types.PowerFailReason

local PayloadValidator = {}



local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isNonNegativeInteger(value: any): boolean
	return isFiniteNumber(value) and value >= 0 and math.floor(value) == value
end



local function sanitizeSequenceId(raw: any): number
	if isNonNegativeInteger(raw) then return raw end
	return 0
end



function PayloadValidator.validate(envelope: any): (boolean, PowerFailReason?, number)
	if type(envelope) ~= "table" then
		return false, Reasons.InvalidTarget, 0
	end

	local sequenceId = sanitizeSequenceId(envelope.sequenceId)

	if type(envelope.powerName) ~= "string" or envelope.powerName == "" then
		return false, Reasons.UnknownPower, sequenceId
	end

	if not isNonNegativeInteger(envelope.sequenceId) then
		return false, Reasons.InvalidTarget, sequenceId
	end

	if envelope.payload == nil then
		return false, Reasons.InvalidTarget, sequenceId
	end

	
	return true, nil, sequenceId
end

return PayloadValidator
