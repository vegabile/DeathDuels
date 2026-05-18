local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)

local Configs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)
local CancellationToken = require(script.Parent.CancellationToken)
local ClientEventBus = require(script.Parent.ClientEventBus)
local InputPosition = require(script.Parent.InputPosition)
local SFXController = require(script.Parent.SFXController)
local AnimationController = require(script.Parent.AnimationController)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local AnimationsConfigs = require(ReplicatedStorage.Animations.Configs)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

local function knifeTrace(message: string)
end

local KnifeController = {}
type CancellationTokenToken = CancellationToken.Token

local localPlayer = Players.LocalPlayer
local stateMachine = KnifeStateMachine.new()
local sequenceId = 0
local knifeEquipped = false
local remoteName: string = ""
local remoteConnection: RBXScriptConnection? = nil
local safetyTimeoutToken: CancellationTokenToken? = nil
local pendingActionGeneration = 0
local pendingAction: {
	generation: number,
	sequenceId: number,
	actionName: string,
	restOffset: CFrame,
	handle: any,
	markerObserverDisconnect: (() -> ())?,
	releaseToken: CancellationTokenToken?,
}? = nil

local function clearSafetyTimeout()
	CancellationToken.cancel(safetyTimeoutToken)
	safetyTimeoutToken = nil
end

local function clearPendingRelease(snapshot: any)
	if not snapshot then return end
	if snapshot.markerObserverDisconnect then
		snapshot.markerObserverDisconnect()
		snapshot.markerObserverDisconnect = nil
	end
	if snapshot.releaseToken then
		CancellationToken.cancel(snapshot.releaseToken)
		snapshot.releaseToken = nil
	end
end

local function clearPendingAction()
	if pendingAction then
		clearPendingRelease(pendingAction)
		pendingAction = nil
	end
end

local function cancelPending()
	pendingActionGeneration += 1
	clearPendingAction()
	AnimationController.stopCurrent()
	clearSafetyTimeout()
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

local function schedulePendingRelease(actionName: string, profile: any, onRelease: (pending: any) -> ())
	local handle = pendingAction and pendingAction.handle
	local capturedGen = pendingActionGeneration
	local releaseTime = (profile and profile.releaseTime) or AnimationsConfigs.DefaultReleaseTime
	local hardTimeout = releaseTime + AnimationsConfigs.ReleaseTimeoutBuffer
	local fired = false

	local function fireOnce(source: string)
		if fired then return end
		if capturedGen ~= pendingActionGeneration then
			knifeTrace(`release suppressed - stale generation (source={source})`)
			return
		end

		local snapshot = pendingAction
		if not snapshot then return end

		fired = true
		clearPendingRelease(snapshot)
		knifeTrace(`release fired action={actionName} source={source}`)
		onRelease(snapshot)
	end

	if not handle then
		warn(`[KNIFE] [KnifeController] {actionName} release missing animation handle; proceeding without animation`)
		fireOnce("nohandle")
		return
	end

	if handle.isNoop then
		knifeTrace(`release proceeding without animation action={actionName}`)
		fireOnce("noanimation")
		return
	end

	local releaseToken = CancellationToken.new()
	pendingAction.releaseToken = releaseToken
	pendingAction.markerObserverDisconnect = handle.observeMarker(AnimationsConfigs.MarkerNames.Release, function(markerFired: boolean)
		if markerFired then
			fireOnce("marker")
		end
	end)

	CancellationToken.delay(releaseToken, releaseTime, function()
		fireOnce("fallback")
	end)

	CancellationToken.delay(releaseToken, hardTimeout, function()
		if not fired then
			knifeTrace(`hard timeout fired action={actionName}`)
			fireOnce("hardtimeout")
		end
	end)
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
	pendingActionGeneration += 1
	local thisGen = pendingActionGeneration
	local thisSeq = sequenceId

	local character = localPlayer.Character
	if not character then
		knifeTrace("performAction aborted - no character")
		KnifeStateMachine.resetAction(stateMachine, actionName)
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local knifeTool = character:FindFirstChildWhichIsA("Tool")
	local handlePart = knifeTool and knifeTool:FindFirstChild("Handle") :: BasePart?

	if not hrp or not handlePart then
		knifeTrace("performAction aborted - no HRP/handle")
		KnifeStateMachine.resetAction(stateMachine, actionName)
		return
	end

	
	local restOffset = hrp.CFrame:ToObjectSpace(handlePart.CFrame)
	local profile = AnimationProfile.resolve(
		knifeTool.Name,
		SharedConfigs.AnimationProfiles,
		actionName
	)

	local animationId = ""
	if profile then
		animationId = profile.id
	end
	if animationId == "" then
		warn(`[KNIFE] [KnifeController] {actionName} animation missing for {knifeTool.Name}; proceeding without animation`)
	end

	local animHandle = AnimationController.play(character, animationId)
	if animationId ~= "" and animHandle.isNoop then
		warn(`[KNIFE] [KnifeController] {actionName} animation failed to load for {knifeTool.Name}; proceeding without animation`)
	end

	pendingAction = {
		generation = thisGen,
		sequenceId = thisSeq,
		actionName = actionName,
		restOffset = restOffset,
		handle = animHandle,
		markerObserverDisconnect = nil,
		releaseToken = nil,
	}

	
	
	if actionName == "Throw" then
		schedulePendingRelease(actionName, profile, function(snapshot)
			if snapshot.generation ~= pendingActionGeneration then return end

			local currentChar = localPlayer.Character
			local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local currentTool = currentChar and currentChar:FindFirstChildWhichIsA("Tool")
			local currentHandle = currentTool and currentTool:FindFirstChild("Handle") :: BasePart?
			if not currentHrp or not currentHandle then
				knifeTrace("release aborted - character gone")
				return
			end

			local restOrigin = (currentHrp.CFrame * snapshot.restOffset).Position
			local spawnCFrame = currentHandle.CFrame
			local aimTarget = InputPosition.getInputPosition()
			if not aimTarget then
				knifeTrace("release aborted - no aim target")
				return
			end

			local delta = aimTarget - restOrigin
			if delta.Magnitude < 0.01 then
				knifeTrace("release aborted - zero-length delta")
				return
			end

			local direction = delta.Unit
			action.clientExecute(stateMachine, direction, spawnCFrame)

			NetworkRouter:Call(remoteName, {
				desiredAction = actionName,
				directionVector = direction,
				restOrigin = restOrigin,
				spawnCFrame = spawnCFrame,
				sequenceId = snapshot.sequenceId,
			})
			knifeTrace(`Throw release sent remote seq={snapshot.sequenceId}`)
		end)
	else
		action.clientExecute(stateMachine, nil)
		NetworkRouter:Call(remoteName, {
			desiredAction = actionName,
			sequenceId = thisSeq,
		})
	end

	clearSafetyTimeout()
	local safetyToken = CancellationToken.new()
	safetyTimeoutToken = safetyToken
	CancellationToken.delay(safetyToken, action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if safetyTimeoutToken ~= safetyToken then return end
		safetyTimeoutToken = nil
		if sequenceId == thisSeq then
			clearPendingAction()
			KnifeStateMachine.resetAction(stateMachine, actionName)
			knifeTrace(`safety timeout triggered action={actionName} seq={thisSeq}`)
		end
	end)
end

function KnifeController._handleServerResponse(payload: any)
	knifeTrace(`server response {payload and typeof(payload) or "nil"}`)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		knifeTrace(`CooldownReset action={payload.actionName}`)
		KnifeStateMachine.resetAction(stateMachine, payload.actionName)
		clearSafetyTimeout()
		if pendingAction and pendingAction.actionName == payload.actionName then
			clearPendingAction()
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
