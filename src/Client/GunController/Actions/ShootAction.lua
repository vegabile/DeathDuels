local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local AnimationController = require(script.Parent.Parent.Parent.AnimationController)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration
do
	local _profile = AnimationProfile.resolve("SmallPistol", SharedConfigs.AnimationProfiles, AnimationType.Shoot)
	ShootAction.animationId = (_profile and _profile.id) or ""
end

function ShootAction.clientExecute(_state, _directionVector)
	local character = Players.LocalPlayer.Character
	if not character then
		warn("[ShootAction] clientExecute: no character")
		return
	end
	AnimationController.play(character, ShootAction.animationId)
	SFXController.playUI(SharedConfigs.ShootSoundId)
end

return ShootAction
