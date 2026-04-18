--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PayloadValidator = require(ReplicatedStorage.Gun.PayloadValidator)

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

local function baseShoot()
	return {
		desiredAction = "Shoot",
		sequenceId = 1,
		directionVector = Vector3.new(1, 0, 0),
		restOrigin = Vector3.new(0, 5, 0),
	}
end

local function baseReload()
	return {
		desiredAction = "Reload",
		sequenceId = 1,
	}
end

do
	local ok = PayloadValidator.validate(baseShoot())
	check("valid shoot with restOrigin passes", ok)
end

do
	local ok = PayloadValidator.validate(baseReload())
	check("reload without restOrigin passes", ok)
end

do
	local p = baseShoot()
	p.restOrigin = nil
	local ok = PayloadValidator.validate(p)
	check("shoot missing restOrigin rejected", not ok)
end

do
	local p = baseShoot()
	p.restOrigin = 42
	local ok = PayloadValidator.validate(p)
	check("shoot with numeric restOrigin rejected", not ok)
end

print(`\n--- {passed} passed, {failed} failed ---`)
