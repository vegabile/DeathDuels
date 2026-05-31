local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CancellationToken = require(script.Parent.CancellationToken)
local AnimationController = require(script.Parent.AnimationController)
local AnimationsConfigs = require(ReplicatedStorage.Animations.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

type CancellationTokenToken = CancellationToken.Token

--// Shared, side-effecting lifecycle logic for the knife/gun controllers. Operates
--// on a controller-owned `state` table so both weapons drive animation the exact
--// same way. Not a pure data container — it plays animations and schedules timers.
export type LifecycleState = {
	pendingAction: any,
	generation: number,
	idleHandle: any,
	safetyTimeoutToken: CancellationTokenToken?,
}

export type ReleaseOptions = {
	actionName: string,
	profile: any,
	logPrefix: string,
	trace: ((message: string) -> ())?,
}

local WeaponAnimationLifecycle = {}

function WeaponAnimationLifecycle.restartIdle(state: LifecycleState, equipped: boolean, character: Model?, animationProfiles: any)
	if not equipped then return end
	if not character then return end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then return end

	local profile = AnimationProfile.resolve(tool.Name, animationProfiles, AnimationType.Idle)
	if not profile or profile.id == "" then return end
	state.idleHandle = AnimationController.playLooped(character, profile.id)
end

function WeaponAnimationLifecycle.clearSafetyTimeout(state: LifecycleState)
	CancellationToken.cancel(state.safetyTimeoutToken)
	state.safetyTimeoutToken = nil
end

function WeaponAnimationLifecycle.clearPendingRelease(snapshot: any)
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

function WeaponAnimationLifecycle.clearPendingAction(state: LifecycleState)
	if state.pendingAction then
		WeaponAnimationLifecycle.clearPendingRelease(state.pendingAction)
		state.pendingAction = nil
	end
end

function WeaponAnimationLifecycle.schedulePendingRelease(state: LifecycleState, opts: ReleaseOptions, onRelease: (snapshot: any) -> ())
	local actionName = opts.actionName
	local profile = opts.profile
	local logPrefix = opts.logPrefix
	local trace = opts.trace

	local handle = state.pendingAction and state.pendingAction.handle
	local capturedGen = state.generation
	local releaseTime = (profile and profile.releaseTime) or AnimationsConfigs.DefaultReleaseTime
	local hardTimeout = releaseTime + AnimationsConfigs.ReleaseTimeoutBuffer
	local fired = false

	local function fireOnce(source: string)
		if fired then return end
		if capturedGen ~= state.generation then
			if trace then trace(`release suppressed - stale generation (source={source})`) end
			return
		end

		local snapshot = state.pendingAction
		if not snapshot then return end

		fired = true
		WeaponAnimationLifecycle.clearPendingRelease(snapshot)
		if trace then trace(`release fired action={actionName} source={source}`) end
		onRelease(snapshot)
	end

	if not handle then
		warn(`{logPrefix} {actionName} release missing animation handle; proceeding without animation`)
		fireOnce("nohandle")
		return
	end

	if handle.isNoop then
		if trace then trace(`release proceeding without animation action={actionName}`) end
		fireOnce("noanimation")
		return
	end

	local releaseToken = CancellationToken.new()
	state.pendingAction.releaseToken = releaseToken
	state.pendingAction.markerObserverDisconnect = handle.observeMarker(AnimationsConfigs.MarkerNames.Release, function(markerFired: boolean)
		if markerFired then
			fireOnce("marker")
		end
	end)

	CancellationToken.delay(releaseToken, releaseTime, function()
		fireOnce("fallback")
	end)

	CancellationToken.delay(releaseToken, hardTimeout, function()
		if not fired then
			if trace then trace(`hard timeout fired action={actionName}`) end
			fireOnce("hardtimeout")
		end
	end)
end

return WeaponAnimationLifecycle
