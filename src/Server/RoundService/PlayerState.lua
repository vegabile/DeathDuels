local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

local PlayerState = {}
PlayerState.__index = PlayerState

local function cloneDefaultStats()
	local stats = {}
	for key, value in Configs.DEFAULT_STATS do
		stats[key] = value
	end
	return stats
end

function PlayerState.new(player: Player, teamNumber: number)
	return setmetatable({
		player = player,
		team = teamNumber,
		status = Configs.PLAYER_STATUSES.Positioning,
		isInGame = false,
		stats = cloneDefaultStats(),
		matchStats = cloneDefaultStats(),
		positionedThisRound = false,
		_locked = false,
	}, PlayerState)
end

function PlayerState:SetStat(key: string, value: any): boolean
	if self._locked then
		warn(`[PlayerState] State is locked, cannot set {key}`)
		return false
	end

	if self.stats[key] == nil and Configs.DEFAULT_STATS[key] == nil then
		warn(`[PlayerState] Unknown stat key: {key}`)
		return false
	end

	self.stats[key] = value
	return true
end

function PlayerState:GetStat(key: string): any
	if self.stats[key] == nil and Configs.DEFAULT_STATS[key] == nil then
		warn(`[PlayerState] Unknown stat key: {key}`)
	end
	return self.stats[key]
end

function PlayerState:SetMatchStat(key: string, value: any): boolean
	if self.matchStats[key] == nil and Configs.DEFAULT_STATS[key] == nil then
		warn(`[PlayerState] Unknown match stat key: {key}`)
		return false
	end

	self.matchStats[key] = value
	return true
end

function PlayerState:GetMatchStat(key: string): any
	if self.matchStats[key] == nil and Configs.DEFAULT_STATS[key] == nil then
		warn(`[PlayerState] Unknown match stat key: {key}`)
	end
	return self.matchStats[key]
end

function PlayerState:SetAlive(isAlive: boolean)
	if self._locked then
		warn("[PlayerState] State is locked, cannot set alive status")
		return
	end
	self.status = if isAlive then Configs.PLAYER_STATUSES.Alive else Configs.PLAYER_STATUSES.Dead
end

function PlayerState:SetInGame(isInGame: boolean)
	self.isInGame = isInGame
end

function PlayerState:Lock()
	self._locked = true
end

function PlayerState:Unlock()
	self._locked = false
end

function PlayerState:IsLocked(): boolean
	return self._locked
end

function PlayerState:Reset()
	for key, value in Configs.DEFAULT_STATS do
		self.stats[key] = value
	end
	self.status = Configs.PLAYER_STATUSES.Positioning
	self.isInGame = false
	self.positionedThisRound = false
	self._locked = false
end

function PlayerState:Serialize()
	local statsCopy = {}
	for key, value in self.stats do
		statsCopy[key] = value
	end
	local matchStatsCopy = {}
	for key, value in self.matchStats do
		matchStatsCopy[key] = value
	end
	local questCopy = nil
	if type(self.quest) == "table" then
		questCopy = {}
		for key, value in self.quest do
			questCopy[key] = value
		end
	end

	return {
		player = {
			UserId = self.player.UserId,
			Name = self.player.Name,
		},
		team = self.team,
		status = self.status,
		isInGame = self.isInGame,
		stats = statsCopy,
		matchStats = matchStatsCopy,
		quest = questCopy,
	}
end

return PlayerState
