local derive = require(script.Parent.derive)

local snapshot = {
	state = "RoundActive",
	playerStates = {
		{
			player = { UserId = 1, Name = "Local" },
			team = 1,
			status = "Dead",
			isInGame = false,
			stats = {},
		},
		{
			player = { UserId = 2, Name = "Teammate" },
			team = 1,
			status = "Alive",
			isInGame = true,
			stats = {},
		},
		{
			player = { UserId = 3, Name = "Opponent" },
			team = 2,
			status = "Alive",
			isInGame = true,
			stats = {},
		},
		{
			player = { UserId = 4, Name = "Positioning" },
			team = 2,
			status = "Positioning",
			isInGame = false,
			stats = {},
		},
	},
}

local state = derive(snapshot, 1, nil)
assert(state.canSpectate == true, "dead local player can spectate")
assert(#state.availableTargets == 2, "only active in-game players are targets")
assert(state.availableTargets[1] == 2, "teammates are prioritized")
assert(state.availableTargets[2] == 3, "opponents follow teammates")
assert(state.currentTargetUserId == 2, "first available target selected")
assert(state.isSpectating == true, "dead local player with targets is spectating")
assert(state.players[1].isEliminated == true, "players map marks dead local player eliminated")
assert(state.players[3].team == 2, "players map keeps team metadata")

local preserved = derive(snapshot, 1, 3)
assert(preserved.currentTargetUserId == 3, "valid previous target is preserved")

local aliveSnapshot = {
	state = "RoundActive",
	playerStates = {
		{
			player = { UserId = 1, Name = "Local" },
			team = 1,
			status = "Alive",
			isInGame = true,
			stats = {},
		},
		{
			player = { UserId = 2, Name = "Opponent" },
			team = 2,
			status = "Alive",
			isInGame = true,
			stats = {},
		},
	},
}
local aliveState = derive(aliveSnapshot, 1, 2)
assert(aliveState.canSpectate == false, "alive in-game local player cannot spectate")
assert(aliveState.currentTargetUserId == nil, "non-spectating player has no current target")
assert(aliveState.isSpectating == false, "non-spectating player is not spectating")

local missingLocal = derive(snapshot, 999, nil)
assert(missingLocal.canSpectate == false, "missing local user fails closed")
assert(missingLocal.isRoundActive == true, "missing local state preserves round activity")
assert(missingLocal.players[2].team == 1, "missing local state still exposes validated player map")

local invalid = derive({ state = "RoundActive", playerStates = { { player = "bad" } } }, 1, nil)
assert(invalid.canSpectate == false, "invalid snapshot fails closed")

print("[Spectate.derive.test] passed")
return true
