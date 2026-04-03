--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapValidator = require(ReplicatedStorage.Map.MapValidator)

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

-- ─── Type guard ───────────────────────────────────────────────────────────────

do
	local ok, err = MapValidator.validate(123)
	check("rejects non-string", not ok)
	check("non-string error mentions mapName", err ~= nil and err:find("mapName") ~= nil)
end

do
	local ok, err = MapValidator.validate(nil)
	check("rejects nil", not ok)
end

-- ─── Unknown map ──────────────────────────────────────────────────────────────

do
	local ok, err = MapValidator.validate("DoesNotExist")
	check("rejects unknown map name", not ok)
	check("unknown map error mentions the name", err ~= nil and err:find("DoesNotExist") ~= nil)
end

-- ─── Valid map ────────────────────────────────────────────────────────────────

do
	--// Pull a real map name straight from the folder so the test stays in sync
	local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
	if mapsFolder and #mapsFolder:GetChildren() > 0 then
		local realMap = mapsFolder:GetChildren()[1].Name
		local ok, err = MapValidator.validate(realMap)
		check(`accepts real map "{realMap}"`, ok, err)
	else
		print("SKIP: no maps in ReplicatedStorage.Maps to test with")
	end
end

-- ─── Summary ──────────────────────────────────────────────────────────────────

-- Spawn count enforcement

do
	local Configs = require(ReplicatedStorage.Round.Configs)
	local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
	if mapsFolder and #mapsFolder:GetChildren() > 0 then
		local realMap = mapsFolder:GetChildren()[1]
		local redCount = 0
		local blueCount = 0
		for _, desc in realMap:GetDescendants() do
			if desc.Name == Configs.SPAWN_PARTS.Red then redCount += 1 end
			if desc.Name == Configs.SPAWN_PARTS.Blue then blueCount += 1 end
		end
		check(
			`map "{realMap.Name}" has >= {Configs.MAX_PLAYERS_PER_TEAM} red spawns`,
			redCount >= Configs.MAX_PLAYERS_PER_TEAM,
			`found {redCount}`
		)
		check(
			`map "{realMap.Name}" has >= {Configs.MAX_PLAYERS_PER_TEAM} blue spawns`,
			blueCount >= Configs.MAX_PLAYERS_PER_TEAM,
			`found {blueCount}`
		)
	else
		print("SKIP: no maps in ReplicatedStorage.Maps to test spawn counts")
	end
end

do
	local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
	if mapsFolder then
		local tempMap = Instance.new("Folder")
		tempMap.Name = "_TestEmptyMap"
		tempMap.Parent = mapsFolder

		local ok = pcall(function()
			MapValidator.validate("_TestEmptyMap")
		end)

		check("error() fires for map with zero spawn parts", not ok)
		tempMap:Destroy()
	else
		print("SKIP: no Maps folder to test spawn crash")
	end
end

print(`\n{passed} passed, {failed} failed`)
