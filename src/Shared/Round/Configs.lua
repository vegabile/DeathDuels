return {
	GAME_STATES = {
		WaitingForPlayers = "WaitingForPlayers",
		AssigningTeams = "AssigningTeams",
		PreparingPlayers = "PreparingPlayers",
		RoundActive = "RoundActive",
		RoundIntermission = "RoundIntermission",
		GameOver = "GameOver",
		TeleportingOut = "TeleportingOut",
		Aborted = "Aborted",
	},

	PLAYER_STATUSES = {
		Alive = "Alive",
		Dead = "Dead",
		Disconnected = "Disconnected",
		Skipped = "Skipped",
		Positioning = "Positioning",
	},

	COMBAT_ELIGIBLE_ATTRIBUTE = "CombatRoundEligible",

	WAITING_PERIOD = 20,
	ROUND_DURATION = 60,
	ROUND_INTERMISSION_DURATION = 5,
	GAME_OVER_DURATION = 8,
	RESPAWN_DELAY = 3,
	READINESS_GRACE_FIRST_ROUND = 20,
	LATE_TELEPORT_GRACE = 3,
	CHAR_FACT_WAIT_TIMEOUT = 10,
	POSITIONING_OUTER_TIMEOUT = 6,
	DEFAULT_WALK_SPEED = 16,

	REQUIRED_FACTS = {
		"ProfileLoaded",
		"LoadoutResolved",
		"CharacterLoaded",
		"CharacterUsable",
	},


	DEFAULT_LOADOUT = {
		knifeName = "Default",
		gunName = "Default",
		Power = "sprint", 
	},

	KICK_REASONS = {
		InvalidTeleportData = "Invalid match data. Returning to lobby.",
		CharacterLoadTimeout = "Character failed to load in time.",
		TeleportOutFailed = "Unable to return to lobby. Please rejoin.",
	},

	LOBBY_PLACE_ID = 92562692732027,
	RETRY_COUNT = 3,
	EXPONENTIAL_BACKOFF_BASE = 1,
	EXPONENTIAL_BACKOFF_EXPONENT = 2,

	ROUNDS_TO_WIN = 5,
	MAX_ROUNDS = 9,
	COINS_PER_KILL = 10,
	XP_PER_KILL = 100,

	INITIAL_SPAWN_PART = "InitialSpawnBox",

	SPAWN_PARTS = {
		Red = "RedSpawn",
		Blue = "BlueSpawn",
	},

	GAME_MODES = {
		{ name = "1v1", playersPerTeam = 1 },
		{ name = "2v2", playersPerTeam = 2 },
		{ name = "3v3", playersPerTeam = 3 },
		{ name = "4v4", playersPerTeam = 4 },
		{ name = "5v5", playersPerTeam = 5 },
		{ name = "6v6", playersPerTeam = 6 },
	},

	MAX_PLAYERS_PER_TEAM = 6,
	POST_ROUND_SPAWN_PART = "PostRoundSpawnPart",

	LEGAL_TRANSITIONS = {
		WaitingForPlayers = { "AssigningTeams", "Aborted" },
		AssigningTeams = { "PreparingPlayers", "Aborted" },
		PreparingPlayers = { "RoundActive", "Aborted" },
		RoundActive = { "RoundIntermission", "GameOver", "Aborted" },
		RoundIntermission = { "RoundActive", "GameOver", "Aborted" },
		GameOver = { "TeleportingOut" },
		TeleportingOut = {},
		Aborted = { "TeleportingOut" },
	},

	DEFAULT_STATS = {
		kills = 0,
		deaths = 0,
		points = 0,
	},
}
