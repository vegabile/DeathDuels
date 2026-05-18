local RoundScope = require(script.Parent.RoundScope)

RoundScope.Cleanup()
assert(RoundScope._count() == 0, "cleanup starts from empty scope")

RoundScope.Register(nil)
assert(RoundScope._count() == 0, "register ignores non-instances")

local part = Instance.new("Part")
part.Name = "ScopedPart"
part.Parent = workspace
RoundScope.Register(part)
assert(part:GetAttribute(RoundScope.ROUND_SCOPED_ATTRIBUTE) == true, "registered instance is marked round-scoped")
assert(RoundScope._count() == 1, "registered instance increments count")

local cleanupCount = 0
local unregister = RoundScope.RegisterCleanup(function()
	cleanupCount += 1
end)
assert(RoundScope._count() == 2, "cleanup increments count")
unregister()
unregister()
assert(cleanupCount == 1, "cleanup unregister is idempotent")
assert(RoundScope._count() == 1, "manual cleanup removes cleanup from scope")

local cleanupTwo = 0
RoundScope.RegisterCleanup(function()
	cleanupTwo += 1
end)
RoundScope.Cleanup()
assert(part.Parent == nil, "cleanup destroys tracked instances")
assert(cleanupTwo == 1, "cleanup runs remaining cleanups")
assert(RoundScope._count() == 0, "cleanup empties scope")

print("[PowerService.RoundScope.test] passed")
return true
