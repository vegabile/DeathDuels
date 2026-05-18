local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

local ReloadAction = {}

ReloadAction.name = "Reload"
ReloadAction.cooldown = SharedConfigs.ReloadCooldown
ReloadAction.duration = SharedConfigs.ReloadCooldown

do
	local profile = AnimationProfile.resolve("SmallPistol", SharedConfigs.AnimationProfiles, AnimationType.Reload)
	ReloadAction.animationId = (profile and profile.id) or ""
end



function ReloadAction.clientExecute(_state, _directionVector)
end

return ReloadAction
