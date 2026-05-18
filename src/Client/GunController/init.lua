local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)

local AnimationsConfigs = require(ReplicatedStorage.Animations.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)

local Configs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)
local AnimationController = require(script.Parent.AnimationController)
local CancellationToken = require(script.Parent.CancellationToken)
local ClientEventBus = require(script.Parent.ClientEventBus)
local InputPosition = require(script.Parent.InputPosition)
local SFXController = require(script.Parent.SFXController)

local DEBUG = Configs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local GunController = {}
type CancellationTokenToken = CancellationToken.Token

local localPlayer = Players.LocalPlayer
local stateMachine = GunStateMachine.new()
local sequenceId = 0
local gunEquipped = false
local remoteName: string = ""
local remoteConnection: RBXScriptConnection? = nil
local safetyTimeoutToken: CancellationTokenToken? = nil
local pendingActionGeneration = 0
local roundActive = false
local pendingAction: {
	generation: number,
	sequenceId: number,
	actionName: string,
	restOffset: CFrame?,
	handle: any,
	markerObserverDisconnect: (() -> ())?,
	releaseToken: CancellationTokenToken?,
}? = nil
local idleHandle: any = nil

local function restartIdle()
	if not gunEquipped then return end
	local character = localPlayer.Character
	if not character then return end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then return end

	local profile = AnimationProfile.resolve(tool.Name, SharedConfigs.AnimationProfiles, AnimationType.Idle)
	if not profile or profile.id == "" then return end
	idleHandle = AnimationController.playLooped(character, profile.id)
end

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
	idleHandle = nil
	clearSafetyTimeout()
	GunStateMachine.resetAll(stateMachine)
	restartIdle()
end

ClientEventBus:Connect("RoundStateChanged", function(newState: string)
	roundActive = newState == RoundConfigs.GAME_STATES.RoundActive
	if not roundActive then
		cancelPending()
	end
end, { replayLast = true })

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

function GunController.onGunUnequipped()
	gunEquipped = false
	cancelPending()
	AnimationController.stopCurrent()
	debugPrint(DEBUG, `[GunController] Gun unequipped`)
end

local function schedulePendingRelease(profile: any, onRelease: (snapshot: any) -> ())
	local handle = pendingAction and pendingAction.handle
	local capturedGen = pendingActionGeneration
	local releaseTime = (profile and profile.releaseTime) or AnimationsConfigs.DefaultReleaseTime
	local hardTimeout = releaseTime + AnimationsConfigs.ReleaseTimeoutBuffer
	local fired = false

	local function fireOnce(source: string)
		if fired then return end
		if capturedGen ~= pendingActionGeneration then return end

		local snapshot = pendingAction
		if not snapshot then return end

		fired = true
		clearPendingRelease(snapshot)
		onRelease(snapshot)
	end

	if not handle then
		warn("[GunController] Shoot release missing animation handle; proceeding without animation")
		fireOnce("nohandle")
		return
	end

	if handle.isNoop then
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
			fireOnce("hardtimeout")
		end
	end)
end

function GunController.performAction(actionName: string)
	if not gunEquipped then return end
	if not roundActive then
		cancelPending()
		return
	end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = GunStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		debugPrint(DEBUG, `[GunController] Action blocked: {actionName}`)
		return
	end

	sequenceId += 1
	pendingActionGeneration += 1
	local thisGen = pendingActionGeneration
	local thisSeq = sequenceId

	local character = localPlayer.Character
	if not character then
		warn("[GunController] performAction aborted - no character")
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	local tool = character:FindFirstChildWhichIsA("Tool")
	local handlePart = tool and tool:FindFirstChild("Handle") :: BasePart?
	local shootPoint = handlePart and handlePart:FindFirstChild("ShootPoint")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not hrp or not tool then
		warn("[GunController] performAction aborted - missing HRP or tool")
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	if actionName == "Shoot" then
		if not shootPoint then
			warn(`[GunController] Shoot aborted - no ShootPoint attachment on {tool.Name}`)
			GunStateMachine.resetAction(stateMachine, actionName)
			return
		end

		local worldCFrame = shootPoint.WorldCFrame
		local restOffset = hrp.CFrame:ToObjectSpace(worldCFrame)
		pendingAction = {
			generation = thisGen,
			sequenceId = thisSeq,
			actionName = actionName,
			restOffset = restOffset,
			handle = nil,
			markerObserverDisconnect = nil,
			releaseToken = nil,
		}
	else
		warn(`[GunController] unsupported actionName={actionName}`)
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	if idleHandle then
		idleHandle.stop()
		idleHandle = nil
	end

	local profiles = SharedConfigs.AnimationProfiles
	if actionName == "Shoot" then
		local leadIn = AnimationProfile.resolve(tool.Name, profiles, AnimationType.ShootLeadIn)
		local shoot = AnimationProfile.resolve(tool.Name, profiles, AnimationType.Shoot)
		local ids: { string } = {}

		if not shoot or shoot.id == "" then
			warn(`[GunController] Shoot animation missing for {tool.Name}; proceeding without animation`)
		else
			if leadIn and leadIn.id ~= "" then
				table.insert(ids, leadIn.id)
			end
			table.insert(ids, shoot.id)
		end

		pendingAction.handle = AnimationController.playChain(character, ids)
		if #ids > 0 and pendingAction.handle.isNoop then
			warn(`[GunController] Shoot animation failed to load for {tool.Name}; proceeding without animation`)
		end

		schedulePendingRelease(shoot, function(snapshot)
			if snapshot.generation ~= pendingActionGeneration then return end

			local currentChar = localPlayer.Character
			local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not currentHrp then return end

			local restOrigin = (currentHrp.CFrame * snapshot.restOffset).Position
			local aim = InputPosition.getInputPosition()
			if not aim then return end

			local delta = aim - restOrigin
			if delta.Magnitude < 0.01 then return end

			local direction = delta.Unit
			action.clientExecute(stateMachine, direction)

			NetworkRouter:Call(remoteName, {
				desiredAction = actionName,
				directionVector = direction,
				restOrigin = restOrigin,
				sequenceId = snapshot.sequenceId,
			})
		end)
	end

	clearSafetyTimeout()
	local safetyToken = CancellationToken.new()
	safetyTimeoutToken = safetyToken
	CancellationToken.delay(safetyToken, action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if safetyTimeoutToken ~= safetyToken then return end
		safetyTimeoutToken = nil
		if sequenceId == thisSeq then
			clearPendingAction()
			GunStateMachine.resetAction(stateMachine, actionName)
			restartIdle()
		end
	end)
end

function GunController._handleServerResponse(payload: any)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		GunStateMachine.resetAction(stateMachine, payload.actionName)
		clearSafetyTimeout()
		if pendingAction and pendingAction.actionName == payload.actionName then
			clearPendingAction()
		end
		restartIdle()
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
		cancelPending()
		stateMachine.isShooting = payload.overriddenState.isShooting == true
		debugPrint(DEBUG, `[GunController] State overridden by server`)
	elseif payload.payloadType == "ProjectileHitConfirm" then
		debugPrint(DEBUG, `[GunController] Hit confirmed for {payload.actionName}`)
		SFXController.playAt(SharedConfigs.HitSoundId, nil)
		ClientEventBus:Fire("GunHitConfirmed", payload.actionName)
	end
end

function GunController.onPlayerDied()
	gunEquipped = false
	cancelPending()
end

return GunController
