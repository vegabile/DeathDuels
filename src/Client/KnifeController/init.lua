local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)

local Configs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)
local ClientEventBus = require(script.Parent.ClientEventBus)
local InputPosition = require(script.Parent.InputPosition)
local SFXController = require(script.Parent.SFXController)

local DEBUG = Configs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local KnifeController = {}

local localPlayer = Players.LocalPlayer
local stateMachine = KnifeStateMachine.new()
local sequenceId = 0
local knifeEquipped = false
local remoteName: string = ""
local remoteConnection: RBXScriptConnection? = nil
local safetyTimeoutThread: thread? = nil

function KnifeController.onKnifeEquipped()
	knifeEquipped = true
	debugPrint(DEBUG, `[KnifeController] Knife equipped`)

	remoteName = `KnifeAction_{localPlayer.UserId}`

	if remoteConnection then
		remoteConnection:Disconnect()
	end
	remoteConnection = NetworkRouter:Listen(remoteName, function(payload)
		KnifeController._handleServerResponse(payload)
	end)
end

function KnifeController.onKnifeUnequipped()
	knifeEquipped = false
	debugPrint(DEBUG, `[KnifeController] Knife unequipped`)
end

function KnifeController.performAction(actionName: string)
	if not knifeEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = KnifeStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		debugPrint(DEBUG, `[KnifeController] Action blocked by state machine`)
		return
	end

	sequenceId += 1

	local directionVector = nil
	if actionName == "Throw" then
		local character = localPlayer.Character
		local knifeTool = character and character:FindFirstChildWhichIsA("Tool")
		local handle = knifeTool and knifeTool:FindFirstChild("Handle")
		local targetPos = InputPosition.getInputPosition()
		if handle and targetPos then
			local delta = targetPos - handle.Position
			if delta.Magnitude < 0.01 then
				KnifeStateMachine.resetAction(stateMachine, actionName)
				return
			end
			directionVector = delta.Unit
		end
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
			KnifeStateMachine.resetAction(stateMachine, actionName)
			debugPrint(DEBUG, `[KnifeController] Safety timeout triggered for {actionName}`)
		end
	end)
end

function KnifeController._handleServerResponse(payload: any)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		KnifeStateMachine.resetAction(stateMachine, payload.actionName)
		if safetyTimeoutThread then
			task.cancel(safetyTimeoutThread)
			safetyTimeoutThread = nil
		end
		debugPrint(DEBUG, `[KnifeController] Cooldown reset for {payload.actionName}`)

	elseif payload.payloadType == "StateOverride" then
		if payload.sequenceId and payload.sequenceId < sequenceId then
			debugPrint(DEBUG, `[KnifeController] Ignoring stale StateOverride (seq {payload.sequenceId} < {sequenceId})`)
			return
		end
		if type(payload.overriddenState) ~= "table" then
			warn("[KnifeController] StateOverride missing overriddenState table")
			return
		end
		stateMachine.isStabbing = payload.overriddenState.isStabbing == true
		stateMachine.isThrowing = payload.overriddenState.isThrowing == true
		if safetyTimeoutThread then
			task.cancel(safetyTimeoutThread)
			safetyTimeoutThread = nil
		end
		debugPrint(DEBUG, `[KnifeController] State overridden by server`)

	elseif payload.payloadType == "ProjectileHitConfirm" then
		debugPrint(DEBUG, `[KnifeController] Hit confirmed for {payload.actionName}`)
		SFXController.playAt(SharedConfigs.HitSoundId, nil)
		SFXController.playAt(SharedConfigs.StickSoundId, nil)
		ClientEventBus:Fire("KnifeHitConfirmed", payload.actionName)
	end
end

function KnifeController.onPlayerDied()
	KnifeStateMachine.resetAll(stateMachine)
	knifeEquipped = false
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
end

return KnifeController
