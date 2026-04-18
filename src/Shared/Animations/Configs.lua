--// Global animation-system configuration shared by Knife + Gun controllers.
--// Change values here to rename markers or tune fallbacks in one place.
return {
	MarkerNames = {
		Release = "Release",
	},

	--// Used when no profile.releaseTime is configured AND the marker never fires.
	DefaultReleaseTime = 0.2,

	--// Added to releaseTime as a last-resort hard timeout so a broken animation
	--// cannot lock a state machine forever.
	ReleaseTimeoutBuffer = 0.25,

	--// Server-side bound: payload.restOrigin must be within this many studs of the
	--// player's HumanoidRootPart. Catches spoofed origins from a tampered client.
	MaxRestOriginDistance = 8,
}
