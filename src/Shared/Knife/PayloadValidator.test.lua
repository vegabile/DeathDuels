local PayloadValidator = require(script.Parent.PayloadValidator)
local Configs = require(script.Parent.Configs)
local nan = 0 / 0

local function expectInvalid(payload, message)
	local ok, reason = PayloadValidator.validate(payload)
	assert(ok == false, "expected payload to be invalid")
	if message ~= nil then
		assert(string.find(reason, message, 1, true) ~= nil, `expected invalid reason to contain "{message}", got "{tostring(reason)}"`)
	end
end

assert(PayloadValidator.sanitizeSequenceId("bad") == 0, "non-table sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = -1 }) == 0, "negative sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = 1.25 }) == 0, "fractional sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = math.huge }) == 0, "infinite sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = nan }) == 0, "NaN sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = 3 }) == 3, "valid sequence is preserved")

expectInvalid(nil, "Payload is not a table")
expectInvalid({ desiredAction = 1, sequenceId = 1 }, "desiredAction is not a string")
expectInvalid({ desiredAction = "Slash", sequenceId = 1 }, "Unknown action")
expectInvalid({ desiredAction = "Stab", sequenceId = 0 }, "positive integer")
expectInvalid({ desiredAction = "Stab", sequenceId = 1.5 }, "positive integer")
expectInvalid({ desiredAction = "Stab", sequenceId = math.huge }, "sequenceId is not a number")
expectInvalid({ desiredAction = "Stab", sequenceId = nan }, "sequenceId is not a number")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, restOrigin = Vector3.new(0, 0, 0) }, "directionVector is required")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = "bad", restOrigin = Vector3.new(0, 0, 0) }, "directionVector is required")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = Vector3.new(nan, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "directionVector is not a Vector3")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = Vector3.new(math.huge, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "directionVector is not a Vector3")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = Vector3.new(0.01, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "magnitude out of range")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = Vector3.new(Configs.MaxDirectionMagnitude + 0.2, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "magnitude out of range")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = Vector3.new(1, 0, 0) }, "restOrigin is required")
expectInvalid({ desiredAction = "Throw", sequenceId = 1, directionVector = Vector3.new(1, 0, 0), restOrigin = Vector3.new(0, nan, 0) }, "restOrigin is required")
expectInvalid({ desiredAction = "Stab", sequenceId = 1, restOrigin = "bad" }, "restOrigin must be a Vector3")
expectInvalid({ desiredAction = "Stab", sequenceId = 1, restOrigin = Vector3.new(0, 0, math.huge) }, "restOrigin must be a Vector3")

local stabOk, stabReason = PayloadValidator.validate({
	desiredAction = "Stab",
	sequenceId = 1,
})
assert(stabOk == true, stabReason)

local throwOk, throwReason = PayloadValidator.validate({
	desiredAction = "Throw",
	sequenceId = 2,
	directionVector = Vector3.new(1, 0, 0),
	restOrigin = Vector3.new(0, 0, 0),
})
assert(throwOk == true, throwReason)
throwOk, throwReason = PayloadValidator.validate({
	desiredAction = "Throw",
	sequenceId = 3,
	directionVector = Vector3.new(0.1, 0, 0),
	restOrigin = Vector3.new(0, 0, 0),
})
assert(throwOk == true, `minimum throw direction magnitude should be accepted: {tostring(throwReason)}`)
throwOk, throwReason = PayloadValidator.validate({
	desiredAction = "Throw",
	sequenceId = 4,
	directionVector = Vector3.new(Configs.MaxDirectionMagnitude, 0, 0),
	restOrigin = Vector3.new(0, 0, 0),
})
assert(throwOk == true, `maximum throw direction magnitude should be accepted: {tostring(throwReason)}`)
assert(PayloadValidator.normalizeDirection(Vector3.new(0, 4, 0)).Y == 1, "normalizeDirection returns unit vector")

print("[Knife.PayloadValidator.test] passed")
return true
