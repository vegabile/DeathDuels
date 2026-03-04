local Framework = require("../framework")
local describe = Framework.describe
local it = Framework.it
local expect = Framework.expect

local PayloadValidator = require("./PayloadValidator")

return function()
	describe("PayloadValidator.validate - type rejection", function()
		it("rejects non-table payload (string)", function()
			local valid, reason = PayloadValidator.validate("not a table")
			expect(valid):toBe(false)
			expect(reason):toBe("Payload is not a table")
		end)

		it("rejects nil payload", function()
			local valid = PayloadValidator.validate(nil)
			expect(valid):toBe(false)
		end)

		it("rejects number payload", function()
			local valid, reason = PayloadValidator.validate(42)
			expect(valid):toBe(false)
			expect(reason):toBe("Payload is not a table")
		end)

		it("rejects boolean payload", function()
			local valid, reason = PayloadValidator.validate(true)
			expect(valid):toBe(false)
			expect(reason):toBe("Payload is not a table")
		end)

		it("rejects function payload", function()
			local valid, reason = PayloadValidator.validate(function() end)
			expect(valid):toBe(false)
			expect(reason):toBe("Payload is not a table")
		end)
	end)

	describe("PayloadValidator.validate - desiredAction", function()
		it("rejects missing desiredAction", function()
			local valid, reason = PayloadValidator.validate({ sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("desiredAction is not a string")
		end)

		it("rejects non-string desiredAction (number)", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = 42, sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("desiredAction is not a string")
		end)

		it("rejects boolean desiredAction", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = true, sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("desiredAction is not a string")
		end)

		it("rejects table desiredAction", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = {}, sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("desiredAction is not a string")
		end)

		it("rejects unknown action name", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Explode", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action: Explode")
		end)

		it("rejects empty string action", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action: ")
		end)

		it("rejects case-variant 'stab' (lowercase)", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "stab", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action: stab")
		end)

		it("rejects case-variant 'STAB' (uppercase)", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "STAB", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action: STAB")
		end)

		it("rejects case-variant 'throw' (lowercase)", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "throw", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action: throw")
		end)

		it("rejects whitespace-padded 'Stab'", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = " Stab", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action:  Stab")
		end)

		it("rejects action with trailing whitespace", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab ", sequenceId = 1 })
			expect(valid):toBe(false)
			expect(reason):toBe("Unknown action: Stab ")
		end)
	end)

	describe("PayloadValidator.validate - sequenceId", function()
		it("rejects missing sequenceId", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab" })
			expect(valid):toBe(false)
			expect(reason):toBe("sequenceId is not a number")
		end)

		it("rejects non-number sequenceId (string)", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = "one" })
			expect(valid):toBe(false)
			expect(reason):toBe("sequenceId is not a number")
		end)

		it("rejects boolean sequenceId", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = true })
			expect(valid):toBe(false)
			expect(reason):toBe("sequenceId is not a number")
		end)

		it("rejects table sequenceId", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = {} })
			expect(valid):toBe(false)
			expect(reason):toBe("sequenceId is not a number")
		end)

		it("rejects nil sequenceId", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = nil })
			expect(valid):toBe(false)
			expect(reason):toBe("sequenceId is not a number")
		end)

		it("accepts zero sequenceId", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = 0 })
			expect(valid):toBe(true)
		end)

		it("accepts negative sequenceId", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = -1 })
			expect(valid):toBe(true)
		end)

		it("accepts very large sequenceId", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = 999999999 })
			expect(valid):toBe(true)
		end)

		it("accepts fractional sequenceId", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = 1.5 })
			expect(valid):toBe(true)
		end)
	end)

	describe("PayloadValidator.validate - valid payloads", function()
		it("accepts valid stab payload", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = 1 })
			expect(valid):toBe(true)
			expect(reason).toBeNil()
		end)

		it("accepts valid throw payload", function()
			local valid, reason = PayloadValidator.validate({ desiredAction = "Throw", sequenceId = 5 })
			expect(valid):toBe(true)
			expect(reason).toBeNil()
		end)

		it("accepts payload with nil directionVector", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab", sequenceId = 1, directionVector = nil })
			expect(valid):toBe(true)
		end)

		it("accepts payload with extra unknown fields", function()
			local valid = PayloadValidator.validate({
				desiredAction = "Stab",
				sequenceId = 1,
				extraField = "malicious",
				anotherField = 999,
			})
			expect(valid):toBe(true)
		end)

		it("returns nil as second value on success", function()
			local _, reason = PayloadValidator.validate({ desiredAction = "Throw", sequenceId = 1 })
			expect(reason).toBeNil()
		end)
	end)

	describe("PayloadValidator.validate - empty table", function()
		it("rejects empty table", function()
			local valid, reason = PayloadValidator.validate({})
			expect(valid):toBe(false)
			expect(reason):toBe("desiredAction is not a string")
		end)
	end)

	describe("PayloadValidator.validate - validation order", function()
		it("checks desiredAction type before action validity", function()
			local _, reason = PayloadValidator.validate({ desiredAction = 123, sequenceId = 1 })
			expect(reason):toBe("desiredAction is not a string")
		end)

		it("checks desiredAction validity before sequenceId", function()
			local _, reason = PayloadValidator.validate({ desiredAction = "Invalid", sequenceId = "bad" })
			expect(reason):toBe("Unknown action: Invalid")
		end)

		it("checks payload type before any fields", function()
			local _, reason = PayloadValidator.validate("string with desiredAction")
			expect(reason):toBe("Payload is not a table")
		end)
	end)

	describe("PayloadValidator.validate - injection attempts", function()
		it("rejects desiredAction with SQL-like injection", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab'; DROP TABLE--", sequenceId = 1 })
			expect(valid):toBe(false)
		end)

		it("rejects desiredAction with null bytes", function()
			local valid = PayloadValidator.validate({ desiredAction = "Stab\0Throw", sequenceId = 1 })
			expect(valid):toBe(false)
		end)

		it("rejects extremely long action string", function()
			local longString = string.rep("A", 10000)
			local valid = PayloadValidator.validate({ desiredAction = longString, sequenceId = 1 })
			expect(valid):toBe(false)
		end)

		it("accepts valid payload despite extra junk fields", function()
			local valid = PayloadValidator.validate({
				desiredAction = "Stab",
				sequenceId = 1,
				__index = "attack",
				__newindex = function() end,
			})
			expect(valid):toBe(true)
		end)
	end)

	Framework.summary()
end
