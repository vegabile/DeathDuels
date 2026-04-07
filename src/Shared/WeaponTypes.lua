export type KnifeAction = "Throw" | "Stab"

export type ThrowRequest = {
	Origin: Vector3,
	Direction: Vector3,
	Timestamp: number,
}

export type StabRequest = {
	TargetId: number,
	Timestamp: number,
}

export type ShotRequest = {
	Origin: Vector3,
	Direction: Vector3,
	Timestamp: number,
}

export type HitResult = {
	Hit: boolean,
	TargetId: number?,
	Position: Vector3?,
	Normal: Vector3?,
	Damage: number?,
}

export type KnifeState = {
	Owner: Player?,
	Position: Vector3,
	Velocity: Vector3,
	Stuck: boolean,
	StuckTo: Instance?,
	Elapsed: number,
}

export type GunState = {
	Ammo: number,
	MaxAmmo: number,
	LastFiredAt: number,
}

return {}
