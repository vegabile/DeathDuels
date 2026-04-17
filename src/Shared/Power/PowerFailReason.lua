--// Single source of truth for every failure reason produced by PowerService.
--// `Locked` is reserved — unused in v1 (lock == cooldown).
return table.freeze({
	UnknownPower  = "UnknownPower",
	OnCooldown    = "OnCooldown",
	Debounced     = "Debounced",
	Locked        = "Locked",
	InvalidState  = "InvalidState",
	InvalidTarget = "InvalidTarget",
	NoPermission  = "NoPermission",
})
