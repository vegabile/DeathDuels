local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)

local Configs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)
local ClientEventBus = require(script.Parent.ClientEventBus)
local InputPosition = require(script.Parent.InputPosition)
local SFXController = require(script.Parent.SFXController)
local AnimationController = require(script.Parent.AnimationController)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)

local function knifeTrace(message: string)
	print("[KNIFE] " .. message)
end

local KnifeController = {}

local localPlayer = Players.LocalPlayer
local stateMachine = KnifeStateMachine.new()
local sequenceId = 0
local knifeEquipped = false
local remoteName: string = ""
local remoteConnection: RBXScriptConnection? = nil
local safetyTimeoutThread: thread? = nil
local pendingActionGeneration = 0
local pendingAction: {
	generation: number,
	sequenceId: number,
	actionName: string,
	restOffset: CFrame,
	handle: any,
	fallbackTimer: thread?,
	hardTimer: thread?,
}? = nil

local function cancelPending()
	pendingActionGeneration += 1
	if pendingAction then
		if pendingAction.fallbackTimer then task.cancel(pendingAction.fallbackTimer) end
		if pendingAction.hardTimer then task.cancel(pendingAction.hardTimer) end
		pendingAction = nil
	end
	AnimationController.stopCurrent()
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
	KnifeStateMachine.resetAll(stateMachine)
	knifeTrace("cancelPending executed")
end

ClientEventBus:Connect("RoundStateChanged", function(newState: string)
	if newState ~= RoundConfigs.GAME_STATES.RoundActive then
		cancelPending()
	end
end)

function KnifeController.onKnifeEquipped()
	knifeEquipped = true
	knifeTrace("onKnifeEquipped")

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
	cancelPending()
	knifeTrace("onKnifeUnequipped")
end

function KnifeController.performAction(actionName: string)
	knifeTrace(`performAction begin action={actionName} equipped={knifeEquipped} seq={sequenceId}`)
	if not knifeEquipped then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = KnifeStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		knifeTrace(`performAction blocked by state machine action={actionName}`)
		return
	end

	sequenceId += 1
	knifeTrace(`performAction accepted sequence={sequenceId} action={actionName}`)

	local directionVector = nil
	if actionName == "Throw" then
		local character = localPlayer.Character
		knifeTrace(`calculating throw direction for {localPlayer.Name}`)
		local knifeTool = character and character:FindFirstChildWhichIsA("Tool")
		local handle = knifeTool and knifeTool:FindFirstChild("Handle")
		local targetPos = InputPosition.getInputPosition()
		if handle and targetPos then
			local delta = targetPos - handle.Position
			knifeTrace(`throw delta magnitude={delta.Magnitude}`)
			if delta.Magnitude < 0.01 then
				KnifeStateMachine.resetAction(stateMachine, actionName)
				knifeTrace("throw aborted: zero-length delta")
				return
			end
			directionVector = delta.Unit
			knifeTrace(`directionVector={directionVector}`)
		end
	end

	action.clientExecute(stateMachine, directionVector)
	knifeTrace(`clientExecute called for {actionName} dirExists={directionVector ~= nil}`)

	NetworkRouter:Call(remoteName, {
		desiredAction = actionName,
		directionVector = directionVector,
		sequenceId = sequenceId,
	})
	knifeTrace(`sent remote payload action={actionName} seq={sequenceId}`)

	local thisSequence = sequenceId
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
	end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSequence then
			KnifeStateMachine.resetAction(stateMachine, actionName)
			knifeTrace(`safety timeout triggered action={actionName} seq={sequenceId}`)
		end
	end)
end

function KnifeController._handleServerResponse(payload: any)
	knifeTrace(`server response {payload and typeof(payload) or "nil"}`)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		knifeTrace(`CooldownReset action={payload.actionName}`)
		KnifeStateMachine.resetAction(stateMachine, payload.actionName)
		if safetyTimeoutThread then
			task.cancel(safetyTimeoutThread)
			safetyTimeoutThread = nil
		end
		knifeTrace(`cooldown reset handled action={payload.actionName}`)

	elseif payload.payloadType == "StateOverride" then
		if payload.sequenceId and payload.sequenceId < sequenceId then
			knifeTrace(`stale StateOverride ignored seq={payload.sequenceId} localSeq={sequenceId}`)
			return
		end
		if type(payload.overriddenState) ~= "table" then
			warn("[KNIFE] [KnifeController] StateOverride missing overriddenState table")
			return
		end
		cancelPending()
		stateMachine.isStabbing = payload.overriddenState.isStabbing == true
		stateMachine.isThrowing = payload.overriddenState.isThrowing == true
		knifeTrace(`state override set stab={stateMachine.isStabbing} throw={stateMachine.isThrowing}`)
		knifeTrace("state overridden by server")

	elseif payload.payloadType == "ProjectileHitConfirm" then
		knifeTrace(`ProjectileHitConfirm action={payload.actionName}`)
		SFXController.playAt(SharedConfigs.HitSoundId, nil)
		SFXController.playAt(SharedConfigs.StickSoundId, nil)
		ClientEventBus:Fire("KnifeHitConfirmed", payload.actionName)
	end
end

function KnifeController.onPlayerDied()
	cancelPending()
	knifeEquipped = false
end

return KnifeController
