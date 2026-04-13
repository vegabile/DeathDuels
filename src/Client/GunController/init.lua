local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local Configs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)
local ClientEventBus = require(script.Parent.ClientEventBus)
local InputPosition = require(script.Parent.InputPosition)
local SFXController = require(script.Parent.SFXController)

local DEBUG = Configs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local GunController = {}

local localPlayer = Players.LocalPlayer
local stateMachine = GunStateMachine.new()
local sequenceId = 0
local gunEquipped = false
local remoteName: string = ""
local remoteConnection: RBXScriptConnection? = nil
local safetyTimeoutThread: thread? = nil

function GunController.onGunEquipped()
	gunEquipped = true
	debugPrint(DEBUG, `[GunController] Gun equipped`)

	remoteName = `GunAction_{localPlayer.UserId}`

	if remoteConnection then
		remoteConnection:Disconnect()
	end
	remoteConnection = NetworkRouter:Listen(remoteName, function(payload)
		GunController._handleServerResponse(payload)
	end)
end

function GunController.onGunUnequipped()
	gunEquipped = false
	debugPrint(DEBUG, `[GunController] Gun unequipped`)
end

function GunController.performAction(actionName: string)
	if not gunEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = GunStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		debugPrint(DEBUG, `[GunController] Action blocked by state machine`)
		return
	end

	sequenceId += 1

	local directionVector = nil
	local character = localPlayer.Character
	local gunTool = character and character:FindFirstChildWhichIsA("Tool")
	local handle = gunTool and gunTool:FindFirstChild("Handle")
	local shootPoint = handle and handle:FindFirstChild("ShootPoint")

	if shootPoint then
		local targetPos = InputPosition.getInputPosition()
		directionVector = (targetPos - shootPoint.WorldPosition).Unit
	end

	action.clientExecute(stateMachine, directionVector)

	NetworkRouter:Call(remoteName, {
		desiredAction = actionName,
		directionVector = directionVector,
		sequenceId = sequenceId,
	})

	local thisSequence = sequenceId
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
	end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSequence then
			GunStateMachine.resetAction(stateMachine, actionName)
			debugPrint(DEBUG, `[GunController] Safety timeout triggered for {actionName}`)
		end
	end)
end

function GunController._handleServerResponse(payload: any)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		GunStateMachine.resetAction(stateMachine, payload.actionName)
		if safetyTimeoutThread then
			task.cancel(safetyTimeoutThread)
			safetyTimeoutThread = nil
		end
		debugPrint(DEBUG, `[GunController] Cooldown reset for {payload.actionName}`)

	elseif payload.payloadType == "StateOverride" then
		if payload.sequenceId and payload.sequenceId < sequenceId then
			debugPrint(DEBUG, `[GunController] Ignoring stale StateOverride (seq {payload.sequenceId} < {sequenceId})`)
			return
		end
		if type(payload.overriddenState) ~= "table" then
			warn("[GunController] StateOverride missing overriddenState table")
			return
		end
		stateMachine.isShooting = payload.overriddenState.isShooting == true
		if safetyTimeoutThread then
			task.cancel(safetyTimeoutThread)
			safetyTimeoutThread = nil
		end
		debugPrint(DEBUG, `[GunController] State overridden by server`)

	elseif payload.payloadType == "ProjectileHitConfirm" then
		debugPrint(DEBUG, `[GunController] Hit confirmed for {payload.actionName}`)
		SFXController.playAt(SharedConfigs.HitSoundId, nil)
		ClientEventBus:Fire("GunHitConfirmed", payload.actionName)
	end
end

function GunController.onPlayerDied()
	GunStateMachine.resetAll(stateMachine)
	gunEquipped = false
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
end

return GunController
