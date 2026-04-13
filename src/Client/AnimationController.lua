local AnimationController = {}

export type AnimationHandle = { stop: () -> () }

local NOOP_HANDLE: AnimationHandle = { stop = function() end }

function AnimationController.play(character: Model, animationId: string): AnimationHandle
	if animationId == "" then
		warn("AnimationController.play: animationId is blank, skipping playback")
		return NOOP_HANDLE
	end

	local animator = character:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		warn("AnimationController.play: no Animator found on character")
		return NOOP_HANDLE
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not ok then
		warn("AnimationController.play: LoadAnimation failed — " .. tostring(result))
		return NOOP_HANDLE
	end

	local track = result
	track:Play()

	return {
		stop = function()
			if track.IsPlaying then
				track:Stop()
			end
		end,
	}
end

function AnimationController.stopAll(character: Model)
	local animator = character:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		warn("AnimationController.stopAll: no Animator found on character")
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop()
	end
end

return AnimationController
