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
local pendingActionGeneration = 0
local pendingAction: any = nil
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

local function cancelPending()
	pendingActionGeneration += 1
	if pendingAction then
		if pendingAction.fallbackTimer then task.cancel(pendingAction.fallbackTimer) end
		if pendingAction.hardTimer then task.cancel(pendingAction.hardTimer) end
		pendingAction = nil
	end
	AnimationController.stopCurrent()
	idleHandle = nil
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
	GunStateMachine.resetAll(stateMachine)
	restartIdle()  --// if still equipped + active round, slot fills with idle again
end

ClientEventBus:Connect("RoundStateChanged", function(newState: string)
	if newState ~= RoundConfigs.GAME_STATES.RoundActive then
		cancelPending()
	end
end)

function GunController.onGunEquipped()
	gunEquipped = true
	debugPrint(DEBUG, `[GunController] Gun equipped`)

	remoteName = `GunAction_{localPlayer.UserId}`
	if remoteConnection then remoteConnection:Disconnect() end
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
	AnimationController.stopCurrent()  --// cancelPending already called restartIdle which no-ops when !gunEquipped
	debugPrint(DEBUG, `[GunController] Gun unequipped`)
end

local function schedulePendingRelease(profile: any, onRelease: (snapshot: any) -> ())
	local handle = pendingAction and pendingAction.handle
	if not handle then
		warn("[GunController] schedulePendingRelease — no animation handle, aborting")
		if pendingAction then
			pendingAction = nil
		end
		return
	end
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
		if snapshot.fallbackTimer then task.cancel(snapshot.fallbackTimer) end
		if snapshot.hardTimer then task.cancel(snapshot.hardTimer) end
		onRelease(snapshot)
	end

	task.spawn(function()
		local markerFired = handle.waitForMarker(AnimationsConfigs.MarkerNames.Release)
		if markerFired then fireOnce("marker") end
	end)

	pendingAction.fallbackTimer = task.delay(releaseTime, function()
		fireOnce("fallback")
	end)

	pendingAction.hardTimer = task.delay(hardTimeout, function()
		if not fired then fireOnce("hardtimeout") end
	end)
end

function GunController.performAction(actionName: string)
	if not gunEquipped then return end

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
		warn(`[GunController] performAction aborted — no character`)
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	local tool = character:FindFirstChildWhichIsA("Tool")
	local handlePart = tool and tool:FindFirstChild("Handle") :: BasePart?
	local shootPoint = handlePart and handlePart:FindFirstChild("ShootPoint")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not hrp or not tool then
		warn(`[GunController] performAction aborted — missing HRP or tool`)
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	if actionName == "Shoot" and shootPoint then
		--// ShootPoint is an Attachment — use its WorldCFrame as the rest-pose reference.
		local worldCFrame = shootPoint.WorldCFrame
		local restOffset = hrp.CFrame:ToObjectSpace(worldCFrame)
		pendingAction = {
			generation = thisGen,
			sequenceId = thisSeq,
			actionName = actionName,
			restOffset = restOffset,
			handle = nil,
		}
	elseif actionName == "Reload" then
		pendingAction = {
			generation = thisGen,
			sequenceId = thisSeq,
			actionName = actionName,
			restOffset = nil,
			handle = nil,
		}
	else
		warn(`[GunController] unsupported actionName={actionName} or missing ShootPoint`)
		GunStateMachine.resetAction(stateMachine, actionName)
		return
	end

	--// Stop idle so the action's animation owns the slot.
	if idleHandle then idleHandle = nil end

	local profiles = SharedConfigs.AnimationProfiles
	if actionName == "Shoot" then
		local leadIn = AnimationProfile.resolve(tool.Name, profiles, AnimationType.ShootLeadIn)
		local shoot = AnimationProfile.resolve(tool.Name, profiles, AnimationType.Shoot)
		if not shoot or shoot.id == "" then
			warn(`[GunController] Shoot animation missing for {tool.Name} — aborting action`)
			GunStateMachine.resetAction(stateMachine, actionName)
			pendingAction = nil
			restartIdle()
			return
		end
		local ids: { string } = {}
		if leadIn and leadIn.id ~= "" then table.insert(ids, leadIn.id) end
		table.insert(ids, shoot.id)
		pendingAction.handle = AnimationController.playChain(character, ids)

		schedulePendingRelease(shoot, function(snapshot)
			if snapshot.generation ~= pendingActionGeneration then return end
			local currentChar = localPlayer.Character
			local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not currentHrp then return end

			local restOriginCFrame = currentHrp.CFrame * snapshot.restOffset
			local restOrigin = restOriginCFrame.Position
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
	elseif actionName == "Reload" then
		local reload = AnimationProfile.resolve(tool.Name, profiles, AnimationType.Reload)
		if reload and reload.id ~= "" then
			pendingAction.handle = AnimationController.play(character, reload.id)
		end
		action.clientExecute(stateMachine, nil)
		NetworkRouter:Call(remoteName, {
			desiredAction = actionName,
			sequenceId = thisSeq,
		})
	end

	if safetyTimeoutThread then task.cancel(safetyTimeoutThread) end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSeq then
			GunStateMachine.resetAction(stateMachine, actionName)
			pendingAction = nil
			restartIdle()
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
		pendingAction = nil
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
		stateMachine.isReloading = payload.overriddenState.isReloading == true
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
