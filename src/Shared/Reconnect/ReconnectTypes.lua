export type ReconnectLoadout = {
	knifeName: string?,
	gunName: string?,
	Power: string?,
	powerName: string?,
}

export type ReconnectTicket = {
	status: string,
	userId: number,
	matchId: string,
	placeId: number,
	reservedServerAccessCode: string,
	team: number,
	loadout: ReconnectLoadout?,
	disconnectedAt: number,
	expiresAt: number,
	updatedAt: number?,
	endedAt: number?,
}

export type ReconnectMatchRecord = {
	status: string,
	matchId: string,
	placeId: number,
	reservedServerAccessCode: string,
	updatedAt: number,
	endedAt: number?,
}

return {}
