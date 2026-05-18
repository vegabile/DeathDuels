local RoundScope = {}

local ROUND_SCOPED_ATTRIBUTE = "PowerRoundScoped"
local tracked: { [Instance]: boolean } = {}
local cleanups: { [() -> ()]: boolean } = {}

function RoundScope.Register(instance: Instance?)
	if typeof(instance) ~= "Instance" then
		return
	end

	instance:SetAttribute(ROUND_SCOPED_ATTRIBUTE, true)
	tracked[instance] = true
end

function RoundScope.RegisterCleanup(cleanup: (() -> ())?): () -> ()
	if type(cleanup) ~= "function" then
		return function() end
	end

	local active = true
	local run
	run = function()
		if not active then
			return
		end
		active = false
		cleanups[run] = nil
		local ok, err = pcall(cleanup)
		if not ok then
			warn(`[RoundScope] cleanup failed: {err}`)
		end
	end
	cleanups[run] = true
	return run
end

function RoundScope.Cleanup()
	for instance in tracked do
		tracked[instance] = nil
		if instance.Parent ~= nil then
			instance:Destroy()
		end
	end
	local cleanupList = {}
	for cleanup in cleanups do
		table.insert(cleanupList, cleanup)
	end
	for _, cleanup in cleanupList do
		cleanup()
	end
end

function RoundScope._count(): number
	local count = 0
	for _ in tracked do
		count += 1
	end
	for _ in cleanups do
		count += 1
	end
	return count
end

RoundScope.ROUND_SCOPED_ATTRIBUTE = ROUND_SCOPED_ATTRIBUTE

return RoundScope
