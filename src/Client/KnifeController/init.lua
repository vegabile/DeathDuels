local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
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
local WeaponAnimationLifecycle = require(script.Parent.WeaponAnimationLifecycle)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local AnimationsConfigs = require(ReplicatedStorage.Animations.Configs)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

local function knifeTrace(message: string)
	if Configs.DEBUG_MODE or SharedConfigs.DEBUG_MODE then
		print(`[KnifeController] {message}`)
	end
end

local KnifeController = {}

local localPlayer = Players.LocalPlayer
local stateMachine = KnifeStateMachine.new()
local sequenceId = 0
local knifeEquipped = false
local remoteName: string = ""
local remoteConnection: RBXScriptConnection? = nil
local roundActive = false
local state: WeaponAnimationLifecycle.LifecycleState = {
	pendingAction = nil,
	generation = 0,
	idleHandle = nil,
	safetyTimeoutToken = nil,
}

local function restartIdle()
	WeaponAnimationLifecycle.restartIdle(state, knifeEquipped, localPlayer.Character, SharedConfigs.AnimationProfiles)
end

local function clearSafetyTimeout()
	WeaponAnimationLifecycle.clearSafetyTimeout(state)
end

local function clearPendingAction()
	WeaponAnimationLifecycle.clearPendingAction(state)
end

local heldThrowCleanup: (() -> ())? = nil

local function clearHeldThrow()
	if heldThrowCleanup then
		heldThrowCleanup()
		heldThrowCleanup = nil
	end
end

local function cancelPending()
	state.generation += 1
	clearPendingAction()
	clearHeldThrow()
	AnimationController.stopCurrent()
	state.idleHandle = nil
	clearSafetyTimeout()
	KnifeStateMachine.resetAll(stateMachine)
	restartIdle()
	knifeTrace("cancelPending executed")
end

ClientEventBus:Connect("RoundStateChanged", function(newState: string)
	roundActive = newState == RoundConfigs.GAME_STATES.RoundActive
	if not roundActive then
		cancelPending()
	end
end, { replayLast = true })

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

	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	if tool then
		local toolProfile = SharedConfigs.AnimationProfiles[tool.Name]
		if toolProfile then
			AnimationController.preloadProfile(character, toolProfile)
		end
	end
	restartIdle()
end

function KnifeController.onKnifeUnequipped()
	knifeEquipped = false
	cancelPending()
	knifeTrace("onKnifeUnequipped")
end

local function schedulePendingRelease(actionName: string, profile: any, onRelease: (pending: any) -> ())
	WeaponAnimationLifecycle.schedulePendingRelease(state, {
		actionName = actionName,
		profile = profile,
		logPrefix = "[KNIFE] [KnifeController]",
		trace = knifeTrace,
	}, onRelease)
end

function KnifeController.performAction(actionName: string)
	knifeTrace(`performAction begin action={actionName} equipped={knifeEquipped} seq={sequenceId}`)
	if not knifeEquipped then return end
	if not roundActive then
		cancelPending()
		return
	end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = KnifeStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		knifeTrace(`performAction blocked by state machine action={actionName}`)
		return
	end

	sequenceId += 1
	state.generation += 1
	local thisGen = state.generation
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

	if state.idleHandle then
		state.idleHandle.stop()
		state.idleHandle = nil
	end

	local animHandle = AnimationController.play(character, animationId)
	if animationId ~= "" and animHandle.isNoop then
		warn(`[KNIFE] [KnifeController] {actionName} animation failed to load for {knifeTool.Name}; proceeding without animation`)
	end

	state.pendingAction = {
		generation = thisGen,
		sequenceId = thisSeq,
		actionName = actionName,
		restOffset = restOffset,
		handle = animHandle,
		markerObserverDisconnect = nil,
		releaseToken = nil,
	}

	
	
	local function throwOnRelease(snapshot)
		if snapshot.generation ~= state.generation then return end

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
	end

	local function armSafetyTimeout()
		clearSafetyTimeout()
		local safetyToken = CancellationToken.new()
		state.safetyTimeoutToken = safetyToken
		CancellationToken.delay(safetyToken, action.cooldown + Configs.SafetyTimeoutBuffer, function()
			if state.safetyTimeoutToken ~= safetyToken then return end
			state.safetyTimeoutToken = nil
			if sequenceId == thisSeq then
				clearPendingAction()
				KnifeStateMachine.resetAction(stateMachine, actionName)
				restartIdle()
				knifeTrace(`safety timeout triggered action={actionName} seq={thisSeq}`)
			end
		end)
	end

	if actionName == "Throw" then
		--// Hold the throw at the KnifeStop marker until the player taps or clicks,
		--// then resume so the animation plays through to Release and throws. Release
		--// gating and the safety timeout are armed only on the tap, so the hold can
		--// last indefinitely without the time-based fallbacks firing early.
		local function release()
			schedulePendingRelease(actionName, profile, throwOnRelease)
			armSafetyTimeout()
		end

		if animHandle.isNoop then
			release()
		else
			local stopDisconnect
			stopDisconnect = animHandle.observeMarker(AnimationsConfigs.MarkerNames.KnifeStop, function(fired: boolean)
				if thisGen ~= state.generation then return end
				clearHeldThrow()

				if not fired then
					warn(`[KNIFE] [KnifeController] KnifeStop marker not reached for {knifeTool.Name}; releasing without hold`)
					release()
					return
				end

				if animHandle.track then
					animHandle.track:AdjustSpeed(0)
				end

				local inputConn: RBXScriptConnection
				inputConn = UserInputService.InputBegan:Connect(function(input: InputObject)
					if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
						return
					end
					clearHeldThrow()
					if thisGen ~= state.generation then return end
					if animHandle.track then
						animHandle.track:AdjustSpeed(1)
					end
					release()
				end)
				heldThrowCleanup = function()
					inputConn:Disconnect()
				end
			end)
			heldThrowCleanup = function()
				stopDisconnect()
			end
		end
	else
		action.clientExecute(stateMachine, nil)
		NetworkRouter:Call(remoteName, {
			desiredAction = actionName,
			sequenceId = thisSeq,
		})
		armSafetyTimeout()
	end
end

function KnifeController._handleServerResponse(payload: any)
	knifeTrace(`server response {payload and typeof(payload) or "nil"}`)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		knifeTrace(`CooldownReset action={payload.actionName}`)
		KnifeStateMachine.resetAction(stateMachine, payload.actionName)
		clearSafetyTimeout()
		if state.pendingAction and state.pendingAction.actionName == payload.actionName then
			clearPendingAction()
		end
		restartIdle()
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
