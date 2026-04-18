--// AnimationController — singleton-slot animation manager for the local character.
--//
--// Invariant: at most ONE track occupies the module-level currentActiveHandle slot.
--// Any new play call stops the existing handle before starting its own track. This
--// gives the "only one animation at a time" guarantee required by weapon controllers
--// and prevents stale data from an older action contaminating a newer one.

local AnimationController = {}

export type AnimationHandle = {
	stop: () -> (),
	track: AnimationTrack?,
	waitForMarker: (name: string) -> boolean,
	stopped: RBXScriptSignal?,
}

local NOOP_HANDLE: AnimationHandle = {
	stop = function() end,
	track = nil,
	waitForMarker = function(_) return false end,
	stopped = nil,
}

--// Module-level singleton slot.
local currentActiveHandle: AnimationHandle? = nil

--// Cache of AnimationTrack.Length keyed by animationId. Populated by preloadProfile.
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
		warn(`[AnimationController] LoadAnimation failed — {track}`)
		return nil
	end
	return track :: AnimationTrack
end

local function clearSlotIfMatches(handle: AnimationHandle)
	if currentActiveHandle == handle then
		currentActiveHandle = nil
	end
end

local function buildHandle(track: AnimationTrack): AnimationHandle
	local markerResolved: { [string]: boolean } = {}
	local handle: AnimationHandle
	handle = {
		stop = function()
			if track.IsPlaying then
				track:Stop()
			end
			clearSlotIfMatches(handle)
		end,
		track = track,
		stopped = track.Stopped,
		waitForMarker = function(name: string): boolean
			if markerResolved[name] then return false end
			local resolved = false
			local fired = false
			local co = coroutine.running()
			local markerConn
			local stoppedConn

			local function finish(result: boolean)
				if resolved then return end
				resolved = true
				markerResolved[name] = true
				if markerConn then markerConn:Disconnect() end
				if stoppedConn then stoppedConn:Disconnect() end
				fired = result
				if coroutine.status(co) == "suspended" then
					task.spawn(co)
				end
			end

			markerConn = track:GetMarkerReachedSignal(name):Connect(function()
				finish(true)
			end)
			stoppedConn = track.Stopped:Connect(function()
				finish(false)
			end)

			coroutine.yield()
			return fired
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
		warn("[AnimationController] playChain — no Animator on character")
		return NOOP_HANDLE
	end

	--// Filter blanks; if none remain, no-op.
	local playable: { string } = {}
	for _, id in ids do
		if id ~= "" then table.insert(playable, id) end
	end
	if #playable == 0 then
		return NOOP_HANDLE
	end

	local chainStopped = false
	local chainHandle: AnimationHandle
	local activeTrack: AnimationTrack? = nil
	local markerResolved: { [string]: boolean } = {}

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
		waitForMarker = function(name: string): boolean
			if markerResolved[name] then return false end
			local resolved = false
			local fired = false
			local co = coroutine.running()
			local trackedTrack: AnimationTrack? = nil
			local markerConn
			local stoppedConn

			local function cleanup()
				if markerConn then markerConn:Disconnect() markerConn = nil end
				if stoppedConn then stoppedConn:Disconnect() stoppedConn = nil end
			end

			local function finish(result: boolean)
				if resolved then return end
				resolved = true
				markerResolved[name] = true
				cleanup()
				fired = result
				if coroutine.status(co) == "suspended" then
					task.spawn(co)
				end
			end

			local function bind(track: AnimationTrack?)
				if not track or track == trackedTrack then return end
				cleanup()
				trackedTrack = track
				markerConn = track:GetMarkerReachedSignal(name):Connect(function() finish(true) end)
			end

			--// Poll activeTrack on every Heartbeat until chain ends. Cheap: single comparison.
			local heartbeat
			heartbeat = game:GetService("RunService").Heartbeat:Connect(function()
				if resolved or chainStopped then
					heartbeat:Disconnect()
					if not resolved then finish(false) end
					return
				end
				if activeTrack ~= trackedTrack then
					bind(activeTrack)
				end
			end)

			coroutine.yield()
			heartbeat:Disconnect()
			return fired
		end,
	}

	currentActiveHandle = chainHandle

	task.spawn(function()
		for i, id in playable do
			if chainStopped then break end
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
			anim:Destroy()
			if not ok or not track then
				warn(`[AnimationController] playChain LoadAnimation failed at step {i}`)
				break
			end
			activeTrack = track
			chainHandle.track = track
			chainHandle.stopped = track.Stopped
			track:Play()
			track.Stopped:Wait()
			if chainStopped then break end
		end
		chainStopped = true
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
		warn("[AnimationController] preloadProfile — no Animator")
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
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
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

--// Retained for backwards compatibility with existing call sites.
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
