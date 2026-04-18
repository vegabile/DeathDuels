local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration

do
	local profile = AnimationProfile.resolve("SmallPistol", SharedConfigs.AnimationProfiles, AnimationType.Shoot)
	ShootAction.animationId = (profile and profile.id) or ""
end

--// Invoked from the release callback in GunController. Animation is already playing via the chain.
function ShootAction.clientExecute(_state, _directionVector)
	SFXController.playUI(SharedConfigs.ShootSoundId)
end

return ShootAction
