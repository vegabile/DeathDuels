local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

local WinConditionEvaluator = {}

function WinConditionEvaluator.isRoundOver(teamOneState, teamTwoState): (boolean, number?)
	local teamOneAlive = teamOneState.alivePlayers
	local teamTwoAlive = teamTwoState.alivePlayers

	if teamOneAlive == 0 and teamTwoAlive == 0 then
		return true, nil
	end

	if teamOneAlive == 0 then
		return true, teamTwoState.teamNumber
	end

	if teamTwoAlive == 0 then
		return true, teamOneState.teamNumber
	end

	return false, nil
end

function WinConditionEvaluator.isGameOver(roundResults: { any }, currentRound: number): (boolean, number?)
	local teamOneWins = 0
	local teamTwoWins = 0

	for _, result in roundResults do
		if result.winningTeam == 1 then
			teamOneWins += 1
		elseif result.winningTeam == 2 then
			teamTwoWins += 1
		end
	end

	if teamOneWins >= Configs.ROUNDS_TO_WIN then
		return true, 1
	end

	if teamTwoWins >= Configs.ROUNDS_TO_WIN then
		return true, 2
	end

	if currentRound >= Configs.MAX_ROUNDS then
		
		if teamOneWins > teamTwoWins then
			return true, 1
		elseif teamTwoWins > teamOneWins then
			return true, 2
		end
		return true, nil
	end

	return false, nil
end

return WinConditionEvaluator
