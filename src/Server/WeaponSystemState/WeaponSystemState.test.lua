--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ServerScriptService = game:GetService("ServerScriptService")

local WeaponSystemState = require(ServerScriptService.WeaponSystemState)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

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

-- ─── Positive signal ─────────────────────────────────────────────────────────
do
	WeaponSystemState._reset()
	ServerEventBus:Fire("WeaponSystemReady", true)
	task.wait()
	check("IsReady() returns true after positive signal", WeaponSystemState.IsReady())
end

-- ─── Negative signal ─────────────────────────────────────────────────────────
do
	WeaponSystemState._reset()
	ServerEventBus:Fire("WeaponSystemReady", false)
	task.wait()
	check("IsReady() returns false after negative signal", not WeaponSystemState.IsReady())
end

-- ─── Signal after call starts (race) ─────────────────────────────────────────
do
	WeaponSystemState._reset()
	local result
	task.spawn(function()
		result = WeaponSystemState.IsReady()
	end)
	task.wait(0.1)
	ServerEventBus:Fire("WeaponSystemReady", true)
	task.wait(0.1)
	check("IsReady() resolves when signal arrives mid-wait", result == true)
end

-- ─── Startup timeout ─────────────────────────────────────────────────────────
do
	WeaponSystemState._reset()
	local start = os.clock()
	local ready = WeaponSystemState.IsReady()
	local elapsed = os.clock() - start
	check("IsReady() returns false on timeout", not ready)
	check("IsReady() honors ~5s deadline", elapsed >= 4.5 and elapsed <= 6.0,
		`elapsed = {elapsed}`)
end

print(`\n──── WeaponSystemState: {passed} passed, {failed} failed ────`)
