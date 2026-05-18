local MapValidator = require(script.Parent.MapValidator)

local ok, reason = MapValidator.validate("TestMap", 1)
assert(ok == true, tostring(reason))

ok, reason = MapValidator.validate(123, 1)
assert(ok == false and reason == "mapName is not a string", "non-string mapName is rejected")

ok, reason = MapValidator.validate("DefinitelyMissing", 1)
assert(ok == false and string.find(reason, "Unknown map", 1, true), "unknown map is rejected")

local mapsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Maps")
local unregistered = Instance.new("Model")
unregistered.Name = "UnregisteredMap"
unregistered.Parent = mapsFolder
local red = Instance.new("Part")
red.Name = "RedSpawn"
red.Parent = unregistered
local blue = Instance.new("Part")
blue.Name = "BlueSpawn"
blue.Parent = unregistered

ok, reason = MapValidator.validate("UnregisteredMap", 1)
assert(ok == false and string.find(reason, "not registered", 1, true), "unregistered map is rejected")

print("[Map.MapValidator.test] passed")
return true
