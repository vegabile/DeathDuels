local EffectUtil = require(script.Parent.EffectUtil)
local RoundScope = require(script.Parent.RoundScope)

RoundScope.Cleanup()
__Test.clearDelayedTasks()

local player = Instance.new("Player")
player.Name = "EffectTester"
player.UserId = 901

local unregisterSlow = EffectUtil.TemporaryAttribute(player, "MoveMult", 0.5, 999)
assert(player:GetAttribute("MoveMult") == 0.5, "temporary attribute is applied")

local unregisterFast = EffectUtil.TemporaryAttribute(player, "MoveMult", 2, 999)
assert(player:GetAttribute("MoveMult") == 2, "newest temporary attribute wins")
unregisterFast()
assert(player:GetAttribute("MoveMult") == 0.5, "removing top attribute restores previous stack entry")
unregisterSlow()
assert(player:GetAttribute("MoveMult") == nil, "removing final attribute clears it")

local character = Instance.new("Model")
local humanoid = Instance.new("Humanoid")
humanoid.Name = "Humanoid"
humanoid.Parent = character
character.Parent = workspace

EffectUtil.TemporaryProperty(player, humanoid, "WalkSpeed", 24, 999)
assert(humanoid.WalkSpeed == 24, "temporary property is applied")
EffectUtil.TemporaryProperty(player, humanoid, "WalkSpeed", 32, 999)
assert(humanoid.WalkSpeed == 32, "newest temporary property wins")
EffectUtil.CleanupPlayer(player)
assert(humanoid.WalkSpeed == 16, "CleanupPlayer restores original property")
assert(player:GetAttribute("MoveMult") == nil, "CleanupPlayer leaves attributes cleared")

__Test.clearDelayedTasks()
RoundScope.Cleanup()

print("[PowerService.EffectUtil.test] passed")
return true
