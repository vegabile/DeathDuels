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

print(`\n{passed} passed, {failed} failed`)
