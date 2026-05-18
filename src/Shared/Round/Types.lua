export type GameState = "WaitingForPlayers" | "AssigningTeams" | "RoundActive"
	| "PreparingPlayers" | "RoundIntermission" | "GameOver" | "TeleportingOut" | "Aborted"

export type PlayerStatus = "Alive" | "Dead" | "Disconnected" | "Skipped"

export type PlayerStateData = {
	player: Player,
	team: number,
	status: PlayerStatus,
	isInGame: boolean,
	stats: { kills: number, deaths: number, points: number, [string]: number },
}

export type TeamStateData = {
	teamNumber: number,
	alivePlayers: number,
	deadPlayers: number,
	disconnectedPlayers: number,
	totalPlayerCount: number,
	originalPlayerCount: number,
	points: number,
}

export type RoundResult = {
	winningTeam: number?,
	stats: {},
}

export type TeleportPlayerEntry = {
	Name: string,
	UserId: number,
}

export type Loadout = {
	knifeName: string?,
	gunName: string?,
	Power: string?,
	powerName: string?,
}

export type TeleportPartyEntry = {
	leaderUserId: number,
	memberUserIds: { number },
}

export type TeleportMetadata = {
	teamOnePlayers: { TeleportPlayerEntry },
	teamTwoPlayers: { TeleportPlayerEntry },
	queueType: number,
	mapName: string,
	timestamp: number,
	loadouts: { [string]: Loadout },
	parties: { [string]: TeleportPartyEntry },
	matchId: string,
	placeId: number,
	reservedServerAccessCode: string,
}

export type PlayerDelta = {
	coinsEarned: number,
	xpEarned: number?,
	actionId: string?,
	kills: number?,
	matchesPlayed: number?,
}

export type GameToLobbyPayload = {
	delta: { [string]: PlayerDelta },
	returnSpawnPartName: string?,
}

export type WinConditionEvaluator = {
	isRoundOver: (teamOneState: TeamStateData, teamTwoState: TeamStateData) -> (boolean, number?),
	isGameOver: (roundResults: { RoundResult }, currentRound: number) -> (boolean, number?),
}

return {}
