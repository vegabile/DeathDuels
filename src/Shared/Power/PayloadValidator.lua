local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local PayloadValidator = {}

--// Best-effort sequenceId extraction — always returns a number ≥ 0, even on failure.
local function sanitizeSequenceId(raw: any): number
	if type(raw) == "number" and raw >= 0 then return raw end
	return 0
end

--// Returns (ok, reason?, sequenceId).
--// sequenceId is always returned so the handler can echo on rejection.
function PayloadValidator.validate(envelope: any): (boolean, string?, number)
	if type(envelope) ~= "table" then
		return false, Reasons.InvalidTarget, 0
	end

	local sequenceId = sanitizeSequenceId(envelope.sequenceId)

	if type(envelope.powerName) ~= "string" or envelope.powerName == "" then
		return false, Reasons.UnknownPower, sequenceId
	end

	if type(envelope.sequenceId) ~= "number" or envelope.sequenceId < 0 then
		return false, Reasons.InvalidTarget, sequenceId
	end

	--// payload is intentionally `any` — per-power validation happens later in Power.validatePayload.
	return true, nil, sequenceId
end

return PayloadValidator
