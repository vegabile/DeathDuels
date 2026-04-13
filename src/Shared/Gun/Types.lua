export type GunStateMachine = {
	isShooting: boolean,
}

export type GunActionConfig = {
	name: string,
	cooldown: number,
	duration: number,
	animationId: string,
}

--// Server actions own authoritative logic (raycast, damage, tracer)
export type ServerGunAction = GunActionConfig & {
	serverExecute: (player: Player, playerState: any, directionVector: Vector3?) -> (),
	serverCleanup: (player: Player, playerState: any) -> (),
}

--// Client actions own prediction (local tracer)
export type ClientGunAction = GunActionConfig & {
	clientExecute: (state: GunStateMachine, directionVector: Vector3?) -> (),
}

export type GunActionPayload = {
	desiredAction: string,
	directionVector: Vector3?,
	sequenceId: number,
}

export type ServerResponsePayload = {
	payloadType: string,
	sequenceId: number?,
	overriddenState: GunStateMachine?,
	actionName: string?,
}

export type KeybindObject = {
	userInputType: Enum.UserInputType?,
	mappedAction: string,
}

return {}
