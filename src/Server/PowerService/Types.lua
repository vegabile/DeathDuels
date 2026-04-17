local SharedTypes = require(game:GetService("ReplicatedStorage").Power.Types)

export type Power = SharedTypes.Power
export type PowerResult = SharedTypes.PowerResult
export type Loadout = SharedTypes.Loadout

export type PowerService = {
	player: Player,
	_equippedPower: Power?,
	_cooldowns: { [string]: number },
	_lastAttempt: { [string]: number },
	_registry: { getPower: (name: string) -> Power? },
}

return {}
