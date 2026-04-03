local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local CLEANUP_DELAY = 10

local SFXController = {}

function SFXController.playAt(soundId: string, position: Vector3?)
	if soundId == "" then
		warn("SFXController.playAt: soundId is blank, skipping")
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.RollOffMaxDistance = 80

	if position then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.CastShadow = false
		anchor.Position = position
		anchor.Parent = workspace
		sound.Parent = anchor
		Debris:AddItem(anchor, CLEANUP_DELAY)
	else
		sound.Parent = workspace
		Debris:AddItem(sound, CLEANUP_DELAY)
	end

	sound:Play()
end

function SFXController.playUI(soundId: string)
	if soundId == "" then
		warn("SFXController.playUI: soundId is blank, skipping")
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = SoundService
	Debris:AddItem(sound, CLEANUP_DELAY)
	sound:Play()
end

return SFXController
