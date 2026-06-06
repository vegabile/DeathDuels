local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ShootCooldown
ReloadAction.duration = SharedConfigs.ShootCooldown
ReloadAction.animationId = ""

function ReloadAction.clientExecute(_state, _directionVector)
end

return ReloadAction
