--// UI-facing slice shared between client and server. Gameplay-tuning fields
--// (durations, speed multipliers, particle configs, etc.) live in
--// src/Server/PowerService/Configs.lua under the concrete-powers spec.
--//
--// Table key = registryName = the Power.name set in each concrete Power module.
--// Adding a power here without a matching Power module means the UI will show
--// it but activation will fail with UnknownPower on the server — that is fine.

local POWERS_BY_NAME = {
	sprint          = { displayName = "Sprint",            cooldown = 10 },
	dash            = { displayName = "Dash",              cooldown = 8  },
	adrenaline      = { displayName = "Adrenaline",        cooldown = 20 },
	launch          = { displayName = "Launch",            cooldown = 8  },
	quickdraw       = { displayName = "Quick Draw",        cooldown = 15 },
	knifespeedboost = { displayName = "Knife Speed Boost", cooldown = 15 },
	weaponbuff      = { displayName = "Weapon Buff",       cooldown = 20 },
	shieldpulse     = { displayName = "Shield Pulse",      cooldown = 15 },
	ghost           = { displayName = "Ghost",             cooldown = 20 },
	reveal          = { displayName = "Reveal",            cooldown = 15 },
	fakeclone       = { displayName = "Fake Clone",        cooldown = 20 },
	smokescreen     = { displayName = "Smoke Screen",      cooldown = 20 },
	blinding        = { displayName = "Blinding",          cooldown = 15 },
}

return {
	POWERS_BY_NAME = POWERS_BY_NAME,
}
