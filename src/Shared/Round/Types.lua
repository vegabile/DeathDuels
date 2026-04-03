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

export type TeleportPayload = {
	roundResults: { RoundResult },
	winningTeam: number?,
	playerStats: { [string]: PlayerStateData },
}

export type WinConditionEvaluator = {
	isRoundOver: (teamOneState: TeamStateData, teamTwoState: TeamStateData) -> (boolean, number?),
	isGameOver: (roundResults: { RoundResult }, currentRound: number) -> (boolean, number?),
}

return {}
