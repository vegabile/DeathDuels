local PayloadValidator = require(script.Parent.PayloadValidator)
local Configs = require(script.Parent.Configs)
local nan = 0 / 0

local function expectInvalid(payload, message)
	local ok = PayloadValidator.validate(payload)
	assert(ok == false, "expected payload to be invalid")
	if message ~= nil then
		local _, reason = PayloadValidator.validate(payload)
		assert(string.find(reason, message, 1, true) ~= nil, `expected invalid reason to contain "{message}", got "{tostring(reason)}"`)
	end
end

assert(PayloadValidator.sanitizeSequenceId(nil) == 0, "nil sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = -1 }) == 0, "negative sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = 1.25 }) == 0, "fractional sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = math.huge }) == 0, "infinite sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = nan }) == 0, "NaN sequence sanitizes to 0")
assert(PayloadValidator.sanitizeSequenceId({ sequenceId = 12 }) == 12, "valid sequence is preserved")

expectInvalid(nil, "Payload is not a table")
expectInvalid({ desiredAction = 1, sequenceId = 1 }, "desiredAction is not a string")
expectInvalid({ desiredAction = "Reload", sequenceId = 1 }, "Unknown action")
expectInvalid({ desiredAction = "Shoot", sequenceId = 0 }, "positive integer")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1.5 }, "positive integer")
expectInvalid({ desiredAction = "Shoot", sequenceId = math.huge }, "sequenceId is not a number")
expectInvalid({ desiredAction = "Shoot", sequenceId = nan }, "sequenceId is not a number")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, restOrigin = Vector3.new(0, 0, 0) }, "directionVector is required")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = "bad", restOrigin = Vector3.new(0, 0, 0) }, "directionVector is required")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(nan, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "directionVector is not a Vector3")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(math.huge, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "directionVector is not a Vector3")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(0.01, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "magnitude out of range")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(Configs.MaxDirectionMagnitude + 0.2, 0, 0), restOrigin = Vector3.new(0, 0, 0) }, "magnitude out of range")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(1, 0, 0) }, "restOrigin is required")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(1, 0, 0), restOrigin = "bad" }, "restOrigin is required")
expectInvalid({ desiredAction = "Shoot", sequenceId = 1, directionVector = Vector3.new(1, 0, 0), restOrigin = Vector3.new(0, nan, 0) }, "restOrigin is required")

local ok, reason = PayloadValidator.validate({
	desiredAction = "Shoot",
	sequenceId = 1,
	directionVector = Vector3.new(1, 0, 0),
	restOrigin = Vector3.new(0, 0, 0),
})
assert(ok == true, reason)
ok, reason = PayloadValidator.validate({
	desiredAction = "Shoot",
	sequenceId = 2,
	directionVector = Vector3.new(0.1, 0, 0),
	restOrigin = Vector3.new(0, 0, 0),
})
assert(ok == true, `minimum direction magnitude should be accepted: {tostring(reason)}`)
ok, reason = PayloadValidator.validate({
	desiredAction = "Shoot",
	sequenceId = 3,
	directionVector = Vector3.new(Configs.MaxDirectionMagnitude, 0, 0),
	restOrigin = Vector3.new(0, 0, 0),
})
assert(ok == true, `maximum direction magnitude should be accepted: {tostring(reason)}`)
assert(PayloadValidator.normalizeDirection(Vector3.new(3, 0, 0)).X == 1, "normalizeDirection returns unit vector")

print("[Gun.PayloadValidator.test] passed")
return true
