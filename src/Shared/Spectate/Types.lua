--// src/Shared/Spectate/Types.lua
--// Data contract for client-derived spectate state.

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
	availableTargets: { number },        --// teammates first (asc userId), then opponents (asc userId)
	currentTargetUserId: number?,
	isSpectating: boolean,
}

return {}
