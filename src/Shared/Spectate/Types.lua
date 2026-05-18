


export type PlayerEntry = {
	team: number,
	isInGame: boolean,
	isEliminated: boolean,
}

export type SpectateClientState = {
	isRoundActive: boolean,
	selfInGame: boolean,
	selfEliminated: boolean,
	players: { [number]: PlayerEntry },
	canSpectate: boolean,
	availableTargets: { number },        
	currentTargetUserId: number?,
	isSpectating: boolean,
}

return {}
