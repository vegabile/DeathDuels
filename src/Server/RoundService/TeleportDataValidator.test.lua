--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TeleportDataValidator = require(ServerScriptService.RoundService.TeleportDataValidator)
local Configs = require(ReplicatedStorage.Round.Configs)

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

local function makeValidBase()
	return {
		teamOnePlayers = { { UserId = 1, Name = "Alice" } },
		teamTwoPlayers = { { UserId = 2, Name = "Bob" } },
		queueType = 1,
		mapName = "TestMap",  --// assumes ReplicatedStorage.Maps.TestMap exists
		timestamp = os.time(),
	}
end

-- ─── Critical fields reject ─────────────────────────────────────────────────
do
	local ok, err, sanitized = TeleportDataValidator.validate(nil)
	check("nil input → false", not ok)
	check("nil input → sanitized nil", sanitized == nil)
	check("nil input → error message", type(err) == "string")
end

do
	local data = makeValidBase()
	data.teamOnePlayers = nil
	local ok = TeleportDataValidator.validate(data)
	check("missing teamOnePlayers → false", not ok)
end

do
	local data = makeValidBase()
	data.mapName = nil
	local ok = TeleportDataValidator.validate(data)
	check("missing mapName → false", not ok)
end

do
	local data = makeValidBase()
	data.queueType = "not-a-number"
	local ok = TeleportDataValidator.validate(data)
	check("invalid queueType → false", not ok)
end

do
	local data = makeValidBase()
	data.timestamp = nil
	local ok = TeleportDataValidator.validate(data)
	check("missing timestamp → false", not ok)
end

-- ─── Loadouts defaulting ────────────────────────────────────────────────────
do
	local data = makeValidBase()
	local ok, _, sanitized = TeleportDataValidator.validate(data)
	check("missing loadouts → ok=true", ok)
	check("sanitized loadouts is table", type(sanitized.loadouts) == "table")
	check("sanitized loadouts['1'] populated", sanitized.loadouts["1"] ~= nil)
	check("sanitized loadouts['2'] populated", sanitized.loadouts["2"] ~= nil)
	check("sanitized loadouts['1'].knifeName = default",
		sanitized.loadouts["1"].knifeName == Configs.DEFAULT_LOADOUT.knifeName)
	check("sanitized loadouts['1'].gunName = default",
		sanitized.loadouts["1"].gunName == Configs.DEFAULT_LOADOUT.gunName)
end

do
	local data = makeValidBase()
	data.loadouts = "nope"
	local ok, _, sanitized = TeleportDataValidator.validate(data)
	check("non-table loadouts → ok=true", ok)
	check("non-table loadouts → filled", sanitized.loadouts["1"] ~= nil)
end

do
	local data = makeValidBase()
	data.loadouts = {
		["1"] = { knifeName = "Shiv", gunName = "Pistol" },
	}
	local ok, _, sanitized = TeleportDataValidator.validate(data)
	check("partial loadouts → ok=true", ok)
	check("provided entry preserved knifeName",
		sanitized.loadouts["1"].knifeName == "Shiv")
	check("provided entry preserved gunName",
		sanitized.loadouts["1"].gunName == "Pistol")
	check("missing entry filled with default",
		sanitized.loadouts["2"].knifeName == Configs.DEFAULT_LOADOUT.knifeName)
end

do
	local data = makeValidBase()
	data.loadouts = {
		["1"] = { knifeName = "Shiv" },
		["2"] = { gunName = "Pistol" },
	}
	local ok, _, sanitized = TeleportDataValidator.validate(data)
	check("nil field → ok=true", ok)
	check("player 1 gunName defaulted",
		sanitized.loadouts["1"].gunName == Configs.DEFAULT_LOADOUT.gunName)
	check("player 2 knifeName defaulted",
		sanitized.loadouts["2"].knifeName == Configs.DEFAULT_LOADOUT.knifeName)
	check("player 1 knifeName preserved",
		sanitized.loadouts["1"].knifeName == "Shiv")
end

do
	local data = makeValidBase()
	data.loadouts = { ["1"] = { knifeName = "Shiv", gunName = "Pistol" } }
	local ok, _, sanitized = TeleportDataValidator.validate(data)
	sanitized.loadouts["1"].knifeName = "Mutated"
	check("mutation isolated from caller", data.loadouts["1"].knifeName == "Shiv")
end

do
	local data = makeValidBase()
	local _, _, sanitized = TeleportDataValidator.validate(data)
	sanitized.loadouts["1"].knifeName = "Mutated"
	check("config DEFAULT_LOADOUT.knifeName unchanged",
		Configs.DEFAULT_LOADOUT.knifeName == "Default")
end

print(`\n──── TeleportDataValidator: {passed} passed, {failed} failed ────`)
