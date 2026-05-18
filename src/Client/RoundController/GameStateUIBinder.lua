local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Round.Configs)
local ClientEventBus = require(script.Parent.Parent.ClientEventBus)

local GameStateUIBinder = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local lastSnapshot = nil

local function countTeamWins(roundResults): (number, number)
	local teamOneWins = 0
	local teamTwoWins = 0

	for _, result in roundResults or {} do
		if result.winningTeam == 1 then
			teamOneWins += 1
		elseif result.winningTeam == 2 then
			teamTwoWins += 1
		end
	end

	return teamOneWins, teamTwoWins
end


-- :)
local function findTextLabel(root: Instance, labelName: string): TextLabel?
	local label = root:FindFirstChild(labelName, true)
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function buildAnnouncement(snapshot): string
	if type(snapshot) ~= "table" then
		return "Waiting for round data..."
	end

	local state = snapshot.state
	local roundNumber = snapshot.roundNumber or 0
	local teamOneState = snapshot.teamStates and snapshot.teamStates[1]
	local teamTwoState = snapshot.teamStates and snapshot.teamStates[2]
	local teamOneAlive = teamOneState and teamOneState.alivePlayers or 0
	local teamTwoAlive = teamTwoState and teamTwoState.alivePlayers or 0

	if state == Configs.GAME_STATES.WaitingForPlayers then
		return "Waiting for players..."
	end
	if state == Configs.GAME_STATES.AssigningTeams then
		return "Assigning teams..."
	end
	if state == Configs.GAME_STATES.PreparingPlayers then
		return "Preparing players..."
	end
	if state == Configs.GAME_STATES.RoundActive then
		return `Round {roundNumber}: Team 1 {teamOneAlive} alive | Team 2 {teamTwoAlive} alive`
	end
	if state == Configs.GAME_STATES.RoundIntermission then
		local lastResult = snapshot.roundResults and snapshot.roundResults[#snapshot.roundResults]
		if lastResult and lastResult.winningTeam then
			return `Round {roundNumber} complete - Team {lastResult.winningTeam} wins`
		end
		return `Round {roundNumber} complete - Draw`
	end
	if state == Configs.GAME_STATES.GameOver then
		local teamOneWins, teamTwoWins = countTeamWins(snapshot.roundResults)
		if teamOneWins > teamTwoWins then
			return "Game over - Team 1 wins the match"
		end
		if teamTwoWins > teamOneWins then
			return "Game over - Team 2 wins the match"
		end
		return "Game over - Draw"
	end
	if state == Configs.GAME_STATES.TeleportingOut then
		return "Returning to lobby..."
	end
	if state == Configs.GAME_STATES.Aborted then
		return "Match aborted."
	end

	return "Round update received."
end

local function applySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	lastSnapshot = snapshot

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local gameStateUI = playerGui:FindFirstChild("GameStateUI")
	if not gameStateUI then
		return
	end

	local teamOneWins, teamTwoWins = countTeamWins(snapshot.roundResults)
	local teamOneScore = findTextLabel(gameStateUI, "Team1Score")
	local teamTwoScore = findTextLabel(gameStateUI, "Team2Score")
	local roundAnnouncer = findTextLabel(gameStateUI, "RoundAnnouncer")

	if teamOneScore then
		teamOneScore.Text = tostring(teamOneWins)
	end
	if teamTwoScore then
		teamTwoScore.Text = tostring(teamTwoWins)
	end
	if roundAnnouncer then
		roundAnnouncer.Text = buildAnnouncement(snapshot)
	end
end

function GameStateUIBinder.Init()
	if initialized then
		return
	end
	initialized = true

	ClientEventBus:Connect("RoundUpdate", applySnapshot)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "GameStateUI" and lastSnapshot then
			applySnapshot(lastSnapshot)
		end
	end)
	playerGui.DescendantAdded:Connect(function(descendant)
		if not lastSnapshot then
			return
		end
		local labelName = descendant.Name
		if labelName == "Team1Score" or labelName == "Team2Score" or labelName == "RoundAnnouncer" then
			applySnapshot(lastSnapshot)
		end
	end)
end

return GameStateUIBinder
