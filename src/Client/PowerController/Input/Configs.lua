--// Tuning for the local cooldown display + safety timeout.
--// Cooldown source of truth lives in src/Shared/Power/Configs.lua.

return {
	COOLDOWN_UPDATE_INTERVAL = 0.1,   --// seconds between button-text refreshes
	PENDING_TIMEOUT_BUFFER   = 1.0,   --// extra seconds past cooldown before the pending safety timeout fires
}
