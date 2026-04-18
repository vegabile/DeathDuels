--// Frozen enum of animation category keys used across weapon animation profiles.
--// Add a new entry here before referencing it from any Configs.AnimationProfiles table.
return table.freeze({
	Idle        = "Idle",
	Throw       = "Throw",
	Stab        = "Stab",
	ShootLeadIn = "ShootLeadIn",
	Shoot       = "Shoot",
	Reload      = "Reload",
})
