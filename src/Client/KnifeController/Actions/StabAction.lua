local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local AnimationController = require(script.Parent.Parent.Parent.AnimationController)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local StabAction = {}

StabAction.name = "Stab"
StabAction.cooldown = SharedConfigs.StabCooldown
StabAction.duration = SharedConfigs.StabDuration
do
	local _profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Stab)
	StabAction.animationId = (_profile and _profile.id) or ""
end

function StabAction.clientExecute(_state, _directionVector)
	local character = Players.LocalPlayer.Character
	if not character then
		warn("[StabAction] clientExecute: no character")
		return
	end
	AnimationController.play(character, StabAction.animationId)
	SFXController.playUI(SharedConfigs.StabSoundId)
end

return StabAction
