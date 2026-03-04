local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)

local StabAction = {}

StabAction.name = "Stab"
StabAction.cooldown = SharedConfigs.StabCooldown
StabAction.duration = SharedConfigs.StabDuration
StabAction.animationId = SharedConfigs.StabAnimationId

function StabAction.clientExecute(_state, _directionVector)
	--// Play stab animation locally
	--// Animation playback will be wired when animation IDs are ready
end

return StabAction
