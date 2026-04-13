local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local AnimationController = require(script.Parent.Parent.Parent.AnimationController)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local StabAction = {}

StabAction.name = "Stab"
StabAction.cooldown = SharedConfigs.StabCooldown
StabAction.duration = SharedConfigs.StabDuration
StabAction.animationId = SharedConfigs.StabAnimationId

function StabAction.clientExecute(_state, _directionVector)
	local character = Players.LocalPlayer.Character
	if not character then
		warn("[StabAction] clientExecute: no character")
		return
	end
	AnimationController.play(character, SharedConfigs.StabAnimationId)
	SFXController.playUI(SharedConfigs.StabSoundId)
end

return StabAction
