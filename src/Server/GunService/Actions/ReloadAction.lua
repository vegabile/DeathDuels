local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ReloadCooldown
ReloadAction.duration = SharedConfigs.ReloadCooldown
ReloadAction.animationId = ""

--// No authoritative logic — reload is purely cosmetic. The existing task.delay(cooldown)
--// path in GunService sends CooldownReset back to the client.
function ReloadAction.serverExecute(_player: Player, _playerState: any, _directionVector: Vector3?, _restOrigin: Vector3?)
end

function ReloadAction.serverCleanup(_player: Player, _playerState: any)
end

return ReloadAction
