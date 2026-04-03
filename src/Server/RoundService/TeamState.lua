local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

local TeamState = {}
TeamState.__index = TeamState

function TeamState.new(teamNumber: number, players: { Player }, playerStates: { [Player]: any })
	return setmetatable({
		teamNumber = teamNumber,
		players = players,
		playerStates = playerStates,
		originalPlayerCount = #players,
	}, TeamState)
end

function TeamState:Recalculate()
	local alive = 0
	local dead = 0
	local disconnected = 0
	local points = 0

	for _, player in self.players do
		local state = self.playerStates[player]
		if not state then
			disconnected += 1
			continue
		end

		if state.status == Configs.PLAYER_STATUSES.Disconnected then
			disconnected += 1
		elseif state.status == Configs.PLAYER_STATUSES.Dead then
			dead += 1
		else
			alive += 1
		end

		points += state.stats.points or 0
	end

	return {
		teamNumber = self.teamNumber,
		alivePlayers = alive,
		deadPlayers = dead,
		disconnectedPlayers = disconnected,
		totalPlayerCount = alive + dead,
		originalPlayerCount = self.originalPlayerCount,
		points = points,
	}
end

function TeamState:GetActivePlayers(): { Player }
	local active = {}
	for _, player in self.players do
		local state = self.playerStates[player]
		if state and state.status == Configs.PLAYER_STATUSES.Alive and state.isInGame then
			table.insert(active, player)
		end
	end
	return active
end

function TeamState:HasFullDisconnect(): boolean
	local snapshot = self:Recalculate()
	return snapshot.totalPlayerCount == 0
end

return TeamState
