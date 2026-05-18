local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local RoundStateMachine = require(script.Parent.RoundStateMachine)

local machine = RoundStateMachine.new()
assert(machine:GetState() == Configs.GAME_STATES.WaitingForPlayers, "round state starts waiting")

local transitions = {}
machine:SetTransitionCallback(function(from, to)
	table.insert(transitions, `{from}->{to}`)
end)

local ok, reason = machine:ValidateTransition(Configs.GAME_STATES.AssigningTeams)
assert(ok == true, tostring(reason))

ok, reason = machine:Transition(Configs.GAME_STATES.RoundActive)
assert(ok == false and string.find(reason, "Illegal transition", 1, true), "illegal transition is rejected")
assert(machine:GetState() == Configs.GAME_STATES.WaitingForPlayers, "illegal transition does not change state")
assert(#transitions == 0, "illegal transition does not fire callback")

assert(machine:Transition(Configs.GAME_STATES.AssigningTeams) == true, "waiting -> assigning is legal")
assert(machine:Transition(Configs.GAME_STATES.PreparingPlayers) == true, "assigning -> preparing is legal")
assert(machine:Transition(Configs.GAME_STATES.RoundActive) == true, "preparing -> active is legal")
assert(table.concat(transitions, ",") == "WaitingForPlayers->AssigningTeams,AssigningTeams->PreparingPlayers,PreparingPlayers->RoundActive", "callbacks record legal transitions")

local valid = machine:GetValidTransitions()
assert(table.find(valid, Configs.GAME_STATES.RoundIntermission) ~= nil, "active round can transition to intermission")
assert(table.find(valid, Configs.GAME_STATES.GameOver) ~= nil, "active round can transition to game over")

machine.currentState = "Broken"
ok, reason = machine:ValidateTransition(Configs.GAME_STATES.RoundActive)
assert(ok == false and string.find(reason, "Unknown state", 1, true), "unknown current state is rejected")

print("[RoundService.RoundStateMachine.test] passed")
return true
