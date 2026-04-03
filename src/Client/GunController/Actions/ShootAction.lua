local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationController = require(script.Parent.Parent.Parent.AnimationController)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration
ShootAction.animationId = SharedConfigs.ShootAnimationId

function ShootAction.clientExecute(_state, _directionVector)
	local character = Players.LocalPlayer.Character
	if not character then
		warn("[ShootAction] clientExecute: no character")
		return
	end
	AnimationController.play(character, SharedConfigs.ShootAnimationId)
	SFXController.playUI(SharedConfigs.ShootSoundId)
end

return ShootAction
