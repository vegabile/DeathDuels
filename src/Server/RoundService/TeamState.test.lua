local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local TeamState = require(script.Parent.TeamState)

local players = {
	{ UserId = 1, Name = "AliveInGame" },
	{ UserId = 2, Name = "Dead" },
	{ UserId = 3, Name = "Disconnected" },
	{ UserId = 4, Name = "Skipped" },
	{ UserId = 5, Name = "Positioning" },
	{ UserId = 6, Name = "MissingState" },
	{ UserId = 7, Name = "AliveOutOfGame" },
}

local playerStates = {
	[players[1]] = { status = Configs.PLAYER_STATUSES.Alive, isInGame = true, stats = { points = 10 } },
	[players[2]] = { status = Configs.PLAYER_STATUSES.Dead, isInGame = false, stats = { points = 2 } },
	[players[3]] = { status = Configs.PLAYER_STATUSES.Disconnected, isInGame = false, stats = { points = 3 } },
	[players[4]] = { status = Configs.PLAYER_STATUSES.Skipped, isInGame = false, stats = { points = 4 } },
	[players[5]] = { status = Configs.PLAYER_STATUSES.Positioning, isInGame = false, stats = { points = 5 } },
	[players[7]] = { status = Configs.PLAYER_STATUSES.Alive, isInGame = false, stats = { points = 7 } },
}

local state = TeamState.new(1, players, playerStates)
local snapshot = state:Recalculate()

assert(snapshot.teamNumber == 1, "snapshot includes team number")
assert(snapshot.alivePlayers == 2, "alive count includes alive players regardless of in-game flag")
assert(snapshot.deadPlayers == 1, "dead count is tracked")
assert(snapshot.disconnectedPlayers == 2, "disconnected count includes missing player state")
assert(snapshot.skippedPlayers == 1, "skipped count is tracked")
assert(snapshot.positioningPlayers == 1, "positioning count is tracked")
assert(snapshot.totalPlayerCount == 5, "total excludes disconnected players")
assert(snapshot.originalPlayerCount == #players, "original player count is retained")
assert(snapshot.points == 31, "points are summed across present states")

local active = state:GetActivePlayers()
assert(#active == 1 and active[1] == players[1], "only alive in-game players are active")
assert(state:HasFullDisconnect() == false, "mixed team is not fully disconnected")

local disconnectedTeam = TeamState.new(2, { players[3], players[6] }, {
	[players[3]] = { status = Configs.PLAYER_STATUSES.Disconnected, isInGame = false, stats = {} },
})
assert(disconnectedTeam:HasFullDisconnect() == true, "team with no counted players is a full disconnect")

print("[RoundService.TeamState.test] passed")
return true
