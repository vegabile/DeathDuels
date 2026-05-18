local RunService = game:GetService("RunService")


local AnimationController = {}

export type AnimationHandle = {
	stop: () -> (),
	track: AnimationTrack?,
	waitForMarker: (name: string) -> boolean,
	observeMarker: (name: string, callback: (fired: boolean) -> ()) -> (() -> ()),
	stopped: RBXScriptSignal?,
	isNoop: boolean,
}

local NOOP_HANDLE: AnimationHandle = {
	stop = function() end,
	track = nil,
	waitForMarker = function(_) return false end,
	observeMarker = function(_, _) return function() end end,
	stopped = nil,
	isNoop = true,
}

local currentActiveHandle: AnimationHandle? = nil
local lengthCache: { [string]: number } = {}

local function getAnimator(character: Model): Animator?
	return character:FindFirstChildWhichIsA("Animator", true) :: Animator?
end

local function loadTrack(character: Model, animationId: string): AnimationTrack?
	if animationId == "" then
		return nil
	end

	local animator = getAnimator(character)
	if not animator then
		warn("[AnimationController] no Animator on character")
		return nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok then
		warn(`[AnimationController] LoadAnimation failed - {track}`)
		return nil
	end

	return track :: AnimationTrack
end

local function clearSlotIfMatches(handle: AnimationHandle)
	if currentActiveHandle == handle then
		currentActiveHandle = nil
	end
end

local function waitForObservedMarker(
	observeMarker: (name: string, callback: (fired: boolean) -> ()) -> (() -> ()),
	name: string
): boolean
	local fired = false
	local co = coroutine.running()
	local disconnect = observeMarker(name, function(result: boolean)
		fired = result
		task.defer(function()
			if coroutine.status(co) == "suspended" then
				task.spawn(co)
			end
		end)
	end)

	coroutine.yield()
	disconnect()
	return fired
end

local function buildHandle(track: AnimationTrack): AnimationHandle
	local markerResolved: { [string]: boolean } = {}
	local handle: AnimationHandle

	local function observeMarker(name: string, callback: (fired: boolean) -> ()): (() -> ())
		if markerResolved[name] then
			return function() end
		end

		local resolved = false
		local markerConn: RBXScriptConnection? = nil
		local stoppedConn: RBXScriptConnection? = nil

		local function cleanup()
			if markerConn then
				markerConn:Disconnect()
				markerConn = nil
			end
			if stoppedConn then
				stoppedConn:Disconnect()
				stoppedConn = nil
			end
		end

		local function finish(result: boolean)
			if resolved then return end
			resolved = true
			markerResolved[name] = true
			cleanup()
			callback(result)
		end

		markerConn = track:GetMarkerReachedSignal(name):Connect(function()
			finish(true)
		end)
		stoppedConn = track.Stopped:Connect(function()
			finish(false)
		end)

		if not track.IsPlaying then
			task.defer(function()
				finish(false)
			end)
		end

		return function()
			if resolved then return end
			resolved = true
			cleanup()
		end
	end

	handle = {
		stop = function()
			if track.IsPlaying then
				track:Stop()
			end
			clearSlotIfMatches(handle)
		end,
		track = track,
		stopped = track.Stopped,
		observeMarker = observeMarker,
		isNoop = false,
		waitForMarker = function(name: string): boolean
			if markerResolved[name] then return false end
			return waitForObservedMarker(observeMarker, name)
		end,
	}

	return handle
end

function AnimationController.stopCurrent()
	if currentActiveHandle then
		currentActiveHandle.stop()
	end
end

function AnimationController.play(character: Model, animationId: string): AnimationHandle
	AnimationController.stopCurrent()
	local track = loadTrack(character, animationId)
	if not track then
		return NOOP_HANDLE
	end

	local handle = buildHandle(track)
	currentActiveHandle = handle
	track:Play()
	return handle
end

function AnimationController.playLooped(character: Model, animationId: string): AnimationHandle
	AnimationController.stopCurrent()
	local track = loadTrack(character, animationId)
	if not track then
		return NOOP_HANDLE
	end

	track.Looped = true
	local handle = buildHandle(track)
	currentActiveHandle = handle
	track:Play()
	return handle
end

function AnimationController.playChain(character: Model, ids: { string }): AnimationHandle
	AnimationController.stopCurrent()
	local animator = getAnimator(character)
	if not animator then
		warn("[AnimationController] playChain - no Animator on character")
		return NOOP_HANDLE
	end

	local playableTracks: { AnimationTrack } = {}
	for i, id in ids do
		if id == "" then
			continue
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		anim:Destroy()
		if ok and track then
			table.insert(playableTracks, track)
		else
			warn(`[AnimationController] playChain skipped unloadable step {i}`)
		end
	end
	if #playableTracks == 0 then
		return NOOP_HANDLE
	end

	local chainStopped = false
	local chainHandle: AnimationHandle
	local activeTrack: AnimationTrack? = nil
	local markerResolved: { [string]: boolean } = {}

	local function observeMarker(name: string, callback: (fired: boolean) -> ()): (() -> ())
		if markerResolved[name] then
			return function() end
		end

		local resolved = false
		local trackedTrack: AnimationTrack? = nil
		local markerConn: RBXScriptConnection? = nil
		local heartbeat: RBXScriptConnection? = nil

		local function cleanup()
			if markerConn then
				markerConn:Disconnect()
				markerConn = nil
			end
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end

		local function finish(result: boolean)
			if resolved then return end
			resolved = true
			markerResolved[name] = true
			cleanup()
			callback(result)
		end

		local function bind(track: AnimationTrack?)
			if not track or track == trackedTrack then return end
			if markerConn then
				markerConn:Disconnect()
				markerConn = nil
			end
			trackedTrack = track
			markerConn = track:GetMarkerReachedSignal(name):Connect(function()
				finish(true)
			end)
		end

		heartbeat = RunService.Heartbeat:Connect(function()
			if resolved then
				cleanup()
				return
			end
			if chainStopped then
				finish(false)
				return
			end
			if activeTrack ~= trackedTrack then
				bind(activeTrack)
			end
		end)

		bind(activeTrack)
		if chainStopped then
			task.defer(function()
				finish(false)
			end)
		end

		return function()
			if resolved then return end
			resolved = true
			cleanup()
		end
	end

	local function stopChain()
		chainStopped = true
		if activeTrack and activeTrack.IsPlaying then
			activeTrack:Stop()
		end
		clearSlotIfMatches(chainHandle)
	end

	chainHandle = {
		stop = stopChain,
		track = nil,
		stopped = nil,
		observeMarker = observeMarker,
		isNoop = false,
		waitForMarker = function(name: string): boolean
			if markerResolved[name] then return false end
			return waitForObservedMarker(observeMarker, name)
		end,
	}

	currentActiveHandle = chainHandle

	task.spawn(function()
		for _, track in playableTracks do
			if chainStopped then break end
			activeTrack = track
			chainHandle.track = track
			chainHandle.stopped = track.Stopped
			track:Play()
			track.Stopped:Wait()
			if chainStopped then break end
		end

		chainStopped = true
		activeTrack = nil
		clearSlotIfMatches(chainHandle)
	end)

	return chainHandle
end

function AnimationController.preloadProfile(
	character: Model,
	profile: { [string]: { id: string, releaseTime: number? } }
): { [string]: number }
	local animator = getAnimator(character)
	if not animator then
		warn("[AnimationController] preloadProfile - no Animator")
		return {}
	end

	local result: { [string]: number } = {}
	for _, entry in profile do
		if entry.id == "" then continue end
		if lengthCache[entry.id] then
			result[entry.id] = lengthCache[entry.id]
			continue
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = entry.id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		anim:Destroy()
		if ok and track then
			lengthCache[entry.id] = track.Length
			result[entry.id] = track.Length
			track:Destroy()
		else
			warn(`[AnimationController] preload failed for {entry.id}`)
		end
	end

	return result
end

function AnimationController.getCachedLength(animationId: string): number?
	return lengthCache[animationId]
end

function AnimationController.stopAll(character: Model)
	AnimationController.stopCurrent()
	local animator = getAnimator(character)
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop()
		end
	end
end

return AnimationController
