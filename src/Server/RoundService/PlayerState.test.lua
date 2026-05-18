local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local PlayerState = require(script.Parent.PlayerState)

local fakePlayer = {
	UserId = 123,
	Name = "Tester",
}

local state = PlayerState.new(fakePlayer, 1)
assert(state.status == Configs.PLAYER_STATUSES.Positioning, "new players begin positioning")
assert(state.isInGame == false, "new players are not in-game until positioned")
assert(state:GetStat("kills") == 0, "default round stats are cloned")
assert(state:GetMatchStat("deaths") == 0, "default match stats are cloned")
assert(state:SetStat("unknown", 1) == false, "unknown round stat is rejected")
assert(state:SetMatchStat("unknown", 1) == false, "unknown match stat is rejected")

state:SetStat("kills", 1)
state:SetMatchStat("kills", 2)
state:SetAlive(true)
state:SetInGame(true)
assert(state.status == Configs.PLAYER_STATUSES.Alive, "SetAlive(true) marks alive")
assert(state.isInGame == true, "SetInGame(true) marks in-game")

state:Lock()
assert(state:IsLocked() == true, "Lock marks state locked")
assert(state:SetStat("kills", 5) == false, "locked state rejects SetStat")
state:SetAlive(false)
assert(state.status == Configs.PLAYER_STATUSES.Alive, "locked state rejects SetAlive")
state:Unlock()
assert(state:IsLocked() == false, "Unlock clears lock")
state:SetAlive(false)
assert(state.status == Configs.PLAYER_STATUSES.Dead, "SetAlive(false) marks dead after unlock")

state:Reset()

assert(state:GetStat("kills") == 0, "round stats reset")
assert(state:GetMatchStat("kills") == 2, "match stats survive reset")
assert(state.status == Configs.PLAYER_STATUSES.Positioning, "reset returns to positioning")
assert(state.isInGame == false, "reset removes in-game flag")
assert(state.positionedThisRound == false, "reset clears positioned flag")
assert(state:IsLocked() == false, "reset unlocks state")

local snapshot = state:Serialize()
assert(type(snapshot.player) == "table", "snapshot player is primitive table")
assert(snapshot.player.UserId == 123, "snapshot includes user id")
assert(snapshot.player.Name == "Tester", "snapshot includes name")
assert(snapshot.matchStats.kills == 2, "snapshot includes match stats")
snapshot.stats.kills = 999
snapshot.matchStats.kills = 999
assert(state:GetStat("kills") == 0, "serialized round stats are copied")
assert(state:GetMatchStat("kills") == 2, "serialized match stats are copied")

print("[RoundService.PlayerState.test] passed")
return true
