local SharedTypes = require(game:GetService("ReplicatedStorage").Gun.Types)

export type PlayerGunState = {
	stateMachine: SharedTypes.GunStateMachine,
	remote: RemoteEvent,
	connections: { RBXScriptConnection },
	lastActionTimestamp: number,
}

return {}
