local Reasons = require(script.Parent.PowerFailReason)
local PayloadValidator = require(script.Parent.PayloadValidator)
local nan = 0 / 0

local function expectInvalid(envelope, expectedReason, expectedSequenceId)
	local ok, reason, sequenceId = PayloadValidator.validate(envelope)
	assert(ok == false, "expected envelope to be invalid")
	assert(reason == expectedReason, `expected reason {expectedReason}, got {tostring(reason)}`)
	assert(sequenceId == expectedSequenceId, `expected sequenceId {expectedSequenceId}, got {tostring(sequenceId)}`)
end

expectInvalid(nil, Reasons.InvalidTarget, 0)
expectInvalid({ sequenceId = 4, payload = {} }, Reasons.UnknownPower, 4)
expectInvalid({ powerName = "", sequenceId = 4, payload = {} }, Reasons.UnknownPower, 4)
expectInvalid({ powerName = "sprint", sequenceId = -1, payload = {} }, Reasons.InvalidTarget, 0)
expectInvalid({ powerName = "sprint", sequenceId = "bad", payload = {} }, Reasons.InvalidTarget, 0)
expectInvalid({ powerName = "sprint", sequenceId = 1.5, payload = {} }, Reasons.InvalidTarget, 0)
expectInvalid({ powerName = "sprint", sequenceId = math.huge, payload = {} }, Reasons.InvalidTarget, 0)
expectInvalid({ powerName = "sprint", sequenceId = nan, payload = {} }, Reasons.InvalidTarget, 0)
expectInvalid({ powerName = "sprint", sequenceId = 9 }, Reasons.InvalidTarget, 9)

local ok, reason, sequenceId = PayloadValidator.validate({
	powerName = "sprint",
	sequenceId = 12,
	payload = {},
})
assert(ok == true, tostring(reason))
assert(reason == nil, "valid envelope has no failure reason")
assert(sequenceId == 12, "valid envelope preserves sequenceId")

print("[Power.PayloadValidator.test] passed")
return true
