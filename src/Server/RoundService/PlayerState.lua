local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

local PlayerState = {}
PlayerState.__index = PlayerState

function PlayerState.new(player: Player, teamNumber: number)
	local stats = {}
	for key, value in Configs.DEFAULT_STATS do
		stats[key] = value
	end

	return setmetatable({
		player = player,
		team = teamNumber,
		status = Configs.PLAYER_STATUSES.Alive,
		isInGame = true,
		stats = stats,
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
	self.status = Configs.PLAYER_STATUSES.Alive
	self.isInGame = true
	self._locked = false
end

function PlayerState:Serialize()
	local statsCopy = {}
	for key, value in self.stats do
		statsCopy[key] = value
	end

	return {
		player = self.player,
		team = self.team,
		status = self.status,
		isInGame = self.isInGame,
		stats = statsCopy,
	}
end

return PlayerState
