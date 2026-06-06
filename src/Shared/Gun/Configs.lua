local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)

return {
	DEBUG_MODE = false,
	ValidActions = { "Shoot", "Reload" },
	MaxDirectionMagnitude = 1.1,
	ShootCooldown = 5,
	ShootDamage = 100,
	ShootSoundId = "",
	HitSoundId = "",
	ShootDuration = 0.1,
	MaxRange = 300,
	TracerDuration = 0.2,
	TracerWidth = 0.1,

	AnimationProfiles = {
		smallpistol = {
			[AnimationType.Idle]        = { id = "rbxassetid://96619245713072" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://113264608677670" },
			[AnimationType.Shoot]       = { id = "rbxassetid://122534551424678", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://120384145507027" },
		},
		sniper = {
			[AnimationType.Idle]        = { id = "rbxassetid://101733777651427" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://137101319815130" },
			[AnimationType.Shoot]       = { id = "rbxassetid://120711448765138", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://86399983877646" },
		},
		scarl = {
			[AnimationType.Idle]        = { id = "rbxassetid://70815001672665" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://120088333046717" },
			[AnimationType.Shoot]       = { id = "rbxassetid://77619571430515", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://85423968755531" },
		},
		colt = {
			[AnimationType.Idle]        = { id = "rbxassetid://77370751920297" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://75000544989482" },
			[AnimationType.Shoot]       = { id = "rbxassetid://94179530175503", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://104520278189806" },
		},
		small = {
			[AnimationType.Idle]        = { id = "rbxassetid://71570030897319" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://135652979782068" },
			[AnimationType.Shoot]       = { id = "rbxassetid://101663035088415", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://100576989281262" },
		},
		revolverscoped = {
			[AnimationType.Idle]        = { id = "rbxassetid://126976016590319" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://113220007620431" },
			[AnimationType.Shoot]       = { id = "rbxassetid://80501693669784", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://72458151968632" },
		},
		ak12 = {
			[AnimationType.Idle]        = { id = "rbxassetid://128506550509926" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://121640580460308" },
			[AnimationType.Shoot]       = { id = "rbxassetid://76817311920411", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://117232551238733" },
		},
		ar15 = {
			[AnimationType.Idle]        = { id = "rbxassetid://71176142972927" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://113786859604861" },
			[AnimationType.Shoot]       = { id = "rbxassetid://128633126454522", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://96123613548130" },
		},
		shotgun = {
			[AnimationType.Idle]        = { id = "rbxassetid://102490499624751" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://140311613211342" },
			[AnimationType.Shoot]       = { id = "rbxassetid://138093451037290", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://135810250185254" },
		},
		gungun = {
			[AnimationType.Idle]        = { id = "rbxassetid://77058695285436" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://138017462059855" },
			[AnimationType.Shoot]       = { id = "rbxassetid://120946372911271", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://104612392128702" },
		},
		smally = {
			[AnimationType.Idle]        = { id = "rbxassetid://89260364399908" },
			[AnimationType.ShootLeadIn] = { id = "rbxassetid://76355899919588" },
			[AnimationType.Shoot]       = { id = "rbxassetid://122904998210887", releaseTime = 0.12 },
			[AnimationType.Reload]      = { id = "rbxassetid://128228877455497" },
		},
	},
}
