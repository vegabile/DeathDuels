local Framework = {}

local results = { passed = 0, failed = 0, errors = {} }

function Framework.describe(suiteName, fn)
	print(`\n--- {suiteName} ---`)
	fn()
end

function Framework.it(testName, fn)
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
		print(`  PASS: {testName}`)
	else
		results.failed += 1
		table.insert(results.errors, `  FAIL: {testName} -> {err}`)
		print(`  FAIL: {testName}`)
		print(`        {err}`)
	end
end

function Framework.expect(value)
	return {
		toBe = function(_, expected)
			if value ~= expected then
				error(`Expected {expected}, got {value}`, 2)
			end
		end,
		toEqual = function(_, expected)
			--// Deep equality — checks both directions for table keys
			if type(value) ~= type(expected) then
				error(`Type mismatch: {type(value)} vs {type(expected)}`, 2)
			end
			if type(value) == "table" then
				for k, v in expected do
					if value[k] ~= v then
						error(`Key '{k}': expected {v}, got {value[k]}`, 2)
					end
				end
				for k in value do
					if expected[k] == nil then
						error(`Unexpected key '{k}' in value`, 2)
					end
				end
			elseif value ~= expected then
				error(`Expected {expected}, got {value}`, 2)
			end
		end,
		toBeNil = function()
			if value ~= nil then
				error(`Expected nil, got {tostring(value)}`, 2)
			end
		end,
		toBeTruthy = function()
			if not value then
				error(`Expected truthy, got {tostring(value)}`, 2)
			end
		end,
		toBeFalsy = function()
			if value then
				error(`Expected falsy, got {tostring(value)}`, 2)
			end
		end,
	}
end

function Framework.summary()
	print("\n=== RESULTS ===")
	for _, err in results.errors do
		print(err)
	end
	print(`\n{results.passed} passed, {results.failed} failed`)
	if results.failed > 0 then
		process.exit(1)
	end
end

function Framework.reset()
	results = { passed = 0, failed = 0, errors = {} }
end

return Framework
