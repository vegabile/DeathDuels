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

	--// Server-owned stab hit window duration in seconds. Tune to match the
	--// authored stab animation length when the ID is uploaded.
	StabHitWindow = 1.0,

	AnimationProfiles = {
		Knife = {
			[AnimationType.Throw] = { id = "rbxassetid://100789163917300", releaseTime = 0.2 },
			[AnimationType.Stab]  = { id = "" },
			[AnimationType.Idle]  = { id = "" },
		},
	},
}
