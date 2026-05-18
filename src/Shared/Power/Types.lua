export type PowerFailReason = "UnknownPower" | "OnCooldown" | "Debounced"
	| "Locked" | "InvalidState" | "InvalidTarget" | "NoPermission"

export type PowerResult = {
	success: boolean,
	reason: PowerFailReason?,
	cooldownEndsAtUnixMs: number?,
	serverNowUnixMs: number?,
}

export type Power = {
	name: string,
	cooldown: number,
	validatePayload: (payload: any) -> (boolean, PowerFailReason?),
	Execute: (self: Power, player: Player, payload: any) -> (),
}

export type ActivateRequest  = { powerName: string, payload: any, sequenceId: number }
export type ActivateResponse = { sequenceId: number, result: PowerResult }

export type Loadout = { Power: string? }

return {}
