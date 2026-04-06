return {
	GAME_STATES = {
		WaitingForPlayers = "WaitingForPlayers",
		AssigningTeams = "AssigningTeams",
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
	},

	WAITING_PERIOD = 10,
	ROUND_DURATION = 60,
	ROUND_INTERMISSION_DURATION = 5,
	GAME_OVER_DURATION = 8,
	RESPAWN_DELAY = 3,
	CHARACTER_LOAD_TIMEOUT = 10,

	LOBBY_PLACE_ID = 0,
	RETRY_COUNT = 3,
	EXPONENTIAL_BACKOFF_BASE = 1,
	EXPONENTIAL_BACKOFF_EXPONENT = 2,

	ROUNDS_TO_WIN = 5,
	MAX_ROUNDS = 9,

	SPAWN_PARTS = {
		Red = "RedPart",
		Blue = "BluePart",
	},

	GAME_MODES = {
		{ name = "1v1", playersPerTeam = 1 },
		{ name = "2v2", playersPerTeam = 2 },
	},

	MAX_PLAYERS_PER_TEAM = 2,

	LEGAL_TRANSITIONS = {
		WaitingForPlayers = { "AssigningTeams", "Aborted" },
		AssigningTeams = { "RoundActive", "Aborted" },
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
