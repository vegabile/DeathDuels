--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)

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

do
	local s = GunStateMachine.new()
	check("initial isReloading false", s.isReloading == false)
end

do
	local s = GunStateMachine.new()
	check("Reload accepted from clear state", GunStateMachine.setActionActive(s, "Reload"))
	check("isReloading true after Reload", s.isReloading == true)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	check("Shoot rejected while reloading", not GunStateMachine.setActionActive(s, "Shoot"))
	check("isShooting stays false when rejected", s.isShooting == false)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Shoot")
	check("Reload rejected while shooting", not GunStateMachine.setActionActive(s, "Reload"))
	check("isReloading stays false when rejected", s.isReloading == false)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	GunStateMachine.resetAction(s, "Reload")
	check("isReloading false after reset", s.isReloading == false)
	check("Shoot accepted after reload reset", GunStateMachine.setActionActive(s, "Shoot"))
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	GunStateMachine.resetAll(s)
	check("resetAll clears isReloading", s.isReloading == false)
	check("resetAll clears isShooting", s.isShooting == false)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	local serialized = GunStateMachine.serialize(s)
	check("serialize includes isReloading", serialized.isReloading == true)
end

do
	local s = GunStateMachine.new()
	GunStateMachine.setActionActive(s, "Reload")
	check("isLocked true while reloading", GunStateMachine.isLocked(s))
end

print(`\n--- {passed} passed, {failed} failed ---`)
