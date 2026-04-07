return {
	Knife = {
		ThrowSpeed = 120,
		ThrowMaxDistance = 150,
		ThrowDamage = 60,
		StabDamage = 40,
		StabRange = 6,
		StabCooldown = 0.4,
		ThrowCooldown = 1.2,
		Gravity = Vector3.new(0, -workspace.Gravity, 0),
		StickDepth = 0.3,
		LifetimeSeconds = 5,
		HitboxRadius = 1.2,
	},

	Gun = {
		Damage = 22,
		HeadshotMultiplier = 2.0,
		MaxAmmo = 12,
		FireRate = 0.15,
		ReloadTime = 1.8,
		MaxRange = 500,
		BulletSpeed = 800,
		SpreadAngle = 1.5,
		TrailLifetime = 0.3,
		TrailColor = Color3.fromRGB(255, 200, 80),
	},

	Validation = {
		MaxTimestampDrift = 0.3,
		MaxOriginDrift = 10,
	},
}
