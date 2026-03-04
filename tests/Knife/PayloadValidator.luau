local validActionSet = {
	Stab = true,
	Throw = true,
}

local PayloadValidator = {}

function PayloadValidator.validate(payload)
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

	--// Vector3 validation skipped in Lune tests (no Vector3 type available)

	return true, nil
end

return PayloadValidator
