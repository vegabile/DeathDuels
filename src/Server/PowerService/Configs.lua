return {
	DEBOUNCE = 0.05,   

	POWERS = {
		Sprint          = { cooldown = 10, durationSec = 2,   speedMult = 1.5 },
		Dash            = { cooldown = 8,  durationSec = 0.3, impulseSpeed = 100 },
		Adrenaline      = { cooldown = 20, durationSec = 5,   speedMult = 1.3, cooldownMult = 0.7 },
		Launch          = { cooldown = 8,  durationSec = 3,   jumpPowerMult = 2.0 },
		QuickDraw       = { cooldown = 15, durationSec = 5,   cooldownMult = 0.5 },
		KnifeSpeedBoost = { cooldown = 15, durationSec = 5,   knifeCooldownMult = 0.74 },
		WeaponBuff      = { cooldown = 20, durationSec = 5,   knifeCooldownMult = 0.74, gunCooldownMult = 0.69 },
		ShieldPulse     = { cooldown = 15, durationSec = 2 },
		Ghost           = { cooldown = 20, durationSec = 4 },
		Reveal          = { cooldown = 15, durationSec = 4 },
		FakeClone       = { cooldown = 20, durationSec = 8,   spawnOffset = 3 },
		SmokeScreen     = { cooldown = 20, durationSec = 6,   spawnForward = 8 },
	},

	BROADCAST_REMOTE = "PowerBroadcast",

	EFFECT_TYPES = {
		Reveal = "Reveal",
	},
}
