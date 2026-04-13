export type GameState = "WaitingForPlayers" | "AssigningTeams" | "RoundActive"
	| "RoundIntermission" | "GameOver" | "TeleportingOut" | "Aborted"

export type PlayerStatus = "Alive" | "Dead" | "Disconnected"

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
}

export type TeleportMetadata = {
	teamOnePlayers: { TeleportPlayerEntry },
	teamTwoPlayers: { TeleportPlayerEntry },
	queueType: number,
	mapName: string,
	timestamp: number,
	loadouts: { [string]: Loadout },
}

export type PlayerDelta = {
	coinsEarned: number,
}

export type GameToLobbyPayload = {
	delta: { [string]: PlayerDelta },
}

export type WinConditionEvaluator = {
	isRoundOver: (teamOneState: TeamStateData, teamTwoState: TeamStateData) -> (boolean, number?),
	isGameOver: (roundResults: { RoundResult }, currentRound: number) -> (boolean, number?),
}

return {}
