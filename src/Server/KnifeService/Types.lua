local SharedTypes = require(game:GetService("ReplicatedStorage").Knife.Types)

export type PlayerKnifeState = {
	stateMachine: SharedTypes.KnifeStateMachine,
	remote: RemoteEvent,
	connections: { RBXScriptConnection },
	lastActionTimestamp: number,
	currentTickConnection: RBXScriptConnection?,
	stabTouchedConn: RBXScriptConnection?,
	alreadyHit: { [Player]: boolean },
}

return {}
