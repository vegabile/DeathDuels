export type KnifeStateMachine = {
	isStabbing: boolean,
	isThrowing: boolean,
}

export type KnifeActionConfig = {
	name: string,
	cooldown: number,
	duration: number,
	animationId: string,
}


export type ServerKnifeAction = KnifeActionConfig & {
	serverExecute: (player: Player, playerState: any, directionVector: Vector3?, restOrigin: Vector3?, spawnCFrame: CFrame?) -> boolean,
	serverCleanup: (player: Player, playerState: any) -> (),
}


export type ClientKnifeAction = KnifeActionConfig & {
	clientExecute: (state: KnifeStateMachine, directionVector: Vector3?) -> (),
}

export type KnifeActionPayload = {
	desiredAction: string,
	directionVector: Vector3?,
	restOrigin: Vector3?,
	spawnCFrame: CFrame?,
	sequenceId: number,
}

export type ServerResponsePayload = {
	payloadType: string,
	sequenceId: number?,
	overriddenState: KnifeStateMachine?,
	actionName: string?,
}

export type KeybindObject = {
	keycode: Enum.KeyCode?,
	mappedAction: string,
}

export type MapInput = { KeybindObject }

export type ProjectileConfig = {
	template: Instance,
	directionVector: Vector3,
	spawnCFrame: CFrame,
	parent: Instance,
	transparency: number,
}

return {}
