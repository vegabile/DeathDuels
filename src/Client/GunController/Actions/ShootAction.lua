local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration
ShootAction.animationId = SharedConfigs.ShootAnimationId

function ShootAction.clientExecute(_state, _directionVector)
	--// Server draws the tracer; client only fires the action
end

return ShootAction
