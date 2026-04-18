--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PayloadValidator = require(ReplicatedStorage.Knife.PayloadValidator)

local passed = 0
local failed = 0

local function check(label: string, condition: boolean, detail: string?)
	if condition then
		print(`PASS: {label}`)
		passed += 1
	else
		print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
		failed += 1
	end
end

local function baseThrow()
	return {
		desiredAction = "Throw",
		sequenceId = 1,
		directionVector = Vector3.new(1, 0, 0),
		restOrigin = Vector3.new(0, 5, 0),
	}
end

local function baseStab()
	return {
		desiredAction = "Stab",
		sequenceId = 1,
	}
end

do
	local ok = PayloadValidator.validate(baseThrow())
	check("valid throw with restOrigin passes", ok)
end

do
	local ok = PayloadValidator.validate(baseStab())
	check("stab without restOrigin passes", ok)
end

do
	local p = baseThrow()
	p.restOrigin = nil
	local ok, err = PayloadValidator.validate(p)
	check("throw missing restOrigin rejected", not ok)
	check("throw missing restOrigin error mentions restOrigin", ok or (err ~= nil and string.find(err, "restOrigin") ~= nil))
end

do
	local p = baseThrow()
	p.restOrigin = "not a vector"
	local ok = PayloadValidator.validate(p)
	check("throw with non-Vector3 restOrigin rejected", not ok)
end

do
	local p = baseThrow()
	p.restOrigin = Vector3.new(1, 2, 3)
	local ok = PayloadValidator.validate(p)
	check("throw with valid Vector3 restOrigin passes", ok)
end

print(`\n--- {passed} passed, {failed} failed ---`)
