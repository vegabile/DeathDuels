local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)

return {
	DEBUG_MODE = false,
	ValidActions = { "Shoot", "Reload" },
	MaxDirectionMagnitude = 1.1,
	ShootCooldown = 5,
	ReloadCooldown = 5,
	ShootDamage = 100,
	ShootSoundId = "",
	HitSoundId = "",
	ShootDuration = 0.1,
	MaxRange = 300,
	TracerDuration = 0.2,
	TracerWidth = 0.1,

	MAX_SHOOT_ORIGIN_DISTANCE = 10,

	AnimationProfiles = {
		SmallPistol = {
			[AnimationType.Idle]        = { id = "rbxassetid://86262836320062" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://109732491974921" },
			[AnimationType.Shoot]       = { id = "rbxassetid://77923963870629", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://73493786997600" },
		},
	},
}
