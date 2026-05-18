local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local WinConditionEvaluator = require(script.Parent.WinConditionEvaluator)

local over, winner = WinConditionEvaluator.isRoundOver({ teamNumber = 1, alivePlayers = 1 }, { teamNumber = 2, alivePlayers = 1 })
assert(over == false and winner == nil, "round continues while both teams have alive players")

over, winner = WinConditionEvaluator.isRoundOver({ teamNumber = 1, alivePlayers = 0 }, { teamNumber = 2, alivePlayers = 2 })
assert(over == true and winner == 2, "team two wins when team one has no alive players")

over, winner = WinConditionEvaluator.isRoundOver({ teamNumber = 1, alivePlayers = 3 }, { teamNumber = 2, alivePlayers = 0 })
assert(over == true and winner == 1, "team one wins when team two has no alive players")

over, winner = WinConditionEvaluator.isRoundOver({ teamNumber = 1, alivePlayers = 0 }, { teamNumber = 2, alivePlayers = 0 })
assert(over == true and winner == nil, "round tie when both teams are eliminated")

local results = {}
for _ = 1, Configs.ROUNDS_TO_WIN do
	table.insert(results, { winningTeam = 1 })
end
over, winner = WinConditionEvaluator.isGameOver(results, Configs.ROUNDS_TO_WIN)
assert(over == true and winner == 1, "game ends when team one reaches rounds to win")

results = {
	{ winningTeam = 1 },
	{ winningTeam = 2 },
	{ winningTeam = nil },
}
over, winner = WinConditionEvaluator.isGameOver(results, 3)
assert(over == false and winner == nil, "game continues before max rounds without required wins")

over, winner = WinConditionEvaluator.isGameOver({
	{ winningTeam = 1 },
	{ winningTeam = 1 },
	{ winningTeam = 2 },
}, Configs.MAX_ROUNDS)
assert(over == true and winner == 1, "max rounds tiebreak uses higher win count")

over, winner = WinConditionEvaluator.isGameOver({
	{ winningTeam = 1 },
	{ winningTeam = 2 },
}, Configs.MAX_ROUNDS)
assert(over == true and winner == nil, "max rounds can end in a tie")

print("[RoundService.WinConditionEvaluator.test] passed")
return true
