local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)

return {
	DEBUG_MODE = false,
	ValidActions = { "Stab", "Throw" },
	MaxDirectionMagnitude = 1.1,
	StabCooldown = 5,
	ThrowCooldown = 5,
	StabSoundId = "",
	ThrowSoundId = "",
	HitSoundId = "",
	StickSoundId = "",
	StabDuration = 0.5,
	ThrowDuration = 0.5,
	StabDamage = 100,
	ThrowDamage = 100,
	ThrowSpeed = 100,
	StuckDespawnTime = 5,
	ProjectileMaxLifetime = 7,

	MAX_STAB_DISTANCE = 15,

	
	
	StabHitWindow = 1.0,

	AnimationProfiles = {
		knife = {
			[AnimationType.Throw]   = { id = "rbxassetid://100789163917300", releaseTime = 0.2 },
			[AnimationType.AirSpin] = { id = "rbxassetid://71769759947827" },
			[AnimationType.Stab]    = { id = "" },
			[AnimationType.Idle]    = { id = "" },
		},
		knife1 = {
			[AnimationType.Throw]   = { id = "rbxassetid://99311516394895", releaseTime = 0.2 },
			[AnimationType.AirSpin] = { id = "rbxassetid://139176115318316" },
			[AnimationType.Stab]    = { id = "" },
			[AnimationType.Idle]    = { id = "" },
		},
	},
}
