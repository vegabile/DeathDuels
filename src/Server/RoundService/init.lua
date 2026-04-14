local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Round.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local RoundStateMachine = require(script.RoundStateMachine)
local WinConditionEvaluator = require(script.WinConditionEvaluator)
local RoundOrchestrator = require(script.RoundOrchestrator)

local Types = require(ReplicatedStorage.Round.Types)
type TeleportMetadata = Types.TeleportMetadata

local TeleportMetadataService = require(script.TeleportMetadataService)

local RoundSystem = {}
RoundSystem.__index = RoundSystem

local function isTeamFullyDisconnected(teamSnapshot): boolean
	if not teamSnapshot then
		return false
	end
	if (teamSnapshot.originalPlayerCount or 0) <= 0 then
		return false
	end
	return teamSnapshot.disconnectedPlayers >= teamSnapshot.originalPlayerCount
end

function RoundSystem.new(metadata: TeleportMetadata)
	TeleportMetadataService.Initialize(metadata)

	local self = setmetatable({}, RoundSystem)

	self._metadata = metadata
	self._positioningDoneEvent = Instance.new("BindableEvent")
	self._expectedPlayerCount = #metadata.teamOnePlayers + #metadata.teamTwoPlayers
	self._pendingPlayers = {} :: { Player }
	self._roundRoster = {} :: { Player }
	self._stateMachine = RoundStateMachine.new()
	self._playerStates = {} :: { [Player]: any }
	self._teamPlayers = { [1] = {}, [2] = {} } :: { [number]: { Player } }
	self._teamStates = {} :: { [number]: any }
	self._roundNumber = 0
	self._roundResults = {}
	self._disconnectedStats = {} :: { [string]: any }
	self._listeners = {} :: { [string]: { (...any) -> () } }
	self._broadcastRemote = NetworkRouter:CreateRemoteEvent("RoundUpdate")
	self._snapshotRemote = NetworkRouter:CreateRemoteFunction("RoundGetSnapshot")
	self._waitTask = nil
	self._roundTimerTask = nil
	self._mapModel = nil
	self._destroyed = false
	self._positioningPlayers = false

	NetworkRouter:Listen("RoundGetSnapshot", function(_player: Player)
		if self._destroyed then
			return nil
		end
		return self:GetSnapshot()
	end)

	self._stateMachine:SetTransitionCallback(function(from: string, to: string)
		self:_onStateChanged(from, to)
	end)

	RoundOrchestrator.enter(Configs.GAME_STATES.WaitingForPlayers, self)

	return self
end

function RoundSystem:RegisterPlayer(player: Player)
	if self._stateMachine:GetState() ~= Configs.GAME_STATES.WaitingForPlayers then
		warn(`[RoundSystem] RegisterPlayer called outside WaitingForPlayers for {player.Name}`)
		return
	end
	table.insert(self._pendingPlayers, player)
	print(`[Round] {player.Name} registered ({#self._pendingPlayers}/{self._expectedPlayerCount})`)
	self:_broadcastUpdate()
	if #self._pendingPlayers >= self._expectedPlayerCount then
		self:_transition(Configs.GAME_STATES.AssigningTeams)
	end
end

function RoundSystem:UnregisterPlayer(player: Player)
	local state = self._stateMachine:GetState()

	if state == Configs.GAME_STATES.WaitingForPlayers then
		local index = table.find(self._pendingPlayers, player)
		if index then table.remove(self._pendingPlayers, index) end
		self:_broadcastUpdate()
		return
	end

	--// Later states: preserve the roster entry. The roster is authoritative for
	--// the round, and downstream iteration relies on PlayerState entries being
	--// present even after disconnect (status flips to Disconnected instead).
	local playerState = self._playerStates[player]
	if playerState then
		playerState.status = Configs.PLAYER_STATUSES.Disconnected
		self._disconnectedStats[tostring(player.UserId)] = playerState:Serialize()
	end

	if state == Configs.GAME_STATES.RoundActive then
		self:_fireEvent("PlayerStatusChanged", player, Configs.PLAYER_STATUSES.Disconnected)
		self:_broadcastUpdate()
		self:_checkWinCondition()
	else
		self:_broadcastUpdate()
	end
end

function RoundSystem:OnPlayerDied(player: Player)
	if self._stateMachine:GetState() ~= Configs.GAME_STATES.RoundActive then
		warn(`[RoundSystem] OnPlayerDied called outside RoundActive for {player.Name}`)
		return
	end
	local playerState = self._playerStates[player]
	if not playerState then
		warn(`[RoundSystem] OnPlayerDied: no state found for {player.Name}`)
		return
	end
	if playerState.status == Configs.PLAYER_STATUSES.Skipped then
		warn(`[RoundSystem] OnPlayerDied: {player.Name} is Skipped; ignoring death (should have been impossible)`)
		return
	end
	playerState:SetAlive(false)
	playerState:SetStat("deaths", playerState:GetStat("deaths") + 1)

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local killerUserId = humanoid and humanoid:GetAttribute("LastDamageSource")
	if killerUserId then
		local killer = Players:GetPlayerByUserId(killerUserId)
		local killerState = killer and self._playerStates[killer]
		if killerState then
			killerState:SetStat("kills", killerState:GetStat("kills") + 1)
		end
	end

	self:_fireEvent("PlayerStatusChanged", player, Configs.PLAYER_STATUSES.Dead)
	self:_broadcastUpdate()
	self:_checkWinCondition()
end

function RoundSystem:GetState(): string
	return self._stateMachine:GetState()
end

function RoundSystem:GetSnapshot()
	local serializedPlayers = {}
	for _, playerState in self._playerStates do
		table.insert(serializedPlayers, playerState:Serialize())
	end
	local teamSnapshots = {}
	for team, teamState in self._teamStates do
		teamSnapshots[team] = teamState:Recalculate()
	end
	return {
		state = self._stateMachine:GetState(),
		roundNumber = self._roundNumber,
		roundResults = self._roundResults,
		playerStates = serializedPlayers,
		teamStates = teamSnapshots,
	}
end

function RoundSystem:Connect(event: string, fn: (...any) -> ()): { Disconnect: () -> () }
	if not self._listeners[event] then
		self._listeners[event] = {}
	end
	local list = self._listeners[event]
	table.insert(list, fn)
	return {
		Disconnect = function()
			local index = table.find(list, fn)
			if index then table.remove(list, index) end
		end,
	}
end

function RoundSystem:Abort()
	self:_transition(Configs.GAME_STATES.Aborted)
end

function RoundSystem:Destroy()
	self._destroyed = true
	if self._waitTask then
		task.cancel(self._waitTask)
		self._waitTask = nil
	end
	if self._roundTimerTask then
		task.cancel(self._roundTimerTask)
		self._roundTimerTask = nil
	end
	if self._mapModel then
		self._mapModel:Destroy()
		self._mapModel = nil
	end
	if self._positioningDoneEvent then
		self._positioningDoneEvent:Destroy()
		self._positioningDoneEvent = nil
	end
	if self._snapshotRemote then
		self._snapshotRemote.OnServerInvoke = nil
		self._snapshotRemote = nil
	end
end

function RoundSystem:_transition(to: string)
	if self._destroyed then return end
	self._stateMachine:Transition(to)
end

function RoundSystem:_onStateChanged(from: string, to: string)
	self:_fireEvent("StateChanged", from, to)
	self:_broadcastUpdate()
	RoundOrchestrator.enter(to, self)
end

function RoundSystem:_checkWinCondition()
	if not self._teamStates[1] or not self._teamStates[2] then return end
	local t1 = self._teamStates[1]:Recalculate()
	local t2 = self._teamStates[2]:Recalculate()
	local teamOneFullyDisconnected = isTeamFullyDisconnected(t1)
	local teamTwoFullyDisconnected = isTeamFullyDisconnected(t2)

	if self._positioningPlayers and not teamOneFullyDisconnected and not teamTwoFullyDisconnected then
		return
	end

	local roundOver, winningTeam
	if teamOneFullyDisconnected and teamTwoFullyDisconnected then
		roundOver, winningTeam = true, nil
	elseif teamOneFullyDisconnected then
		roundOver, winningTeam = true, 2
	elseif teamTwoFullyDisconnected then
		roundOver, winningTeam = true, 1
	else
		roundOver, winningTeam = WinConditionEvaluator.isRoundOver(t1, t2)
	end

	if not roundOver then return end

	if self._roundTimerTask then
		task.cancel(self._roundTimerTask)
		self._roundTimerTask = nil
	end

	table.insert(self._roundResults, { winningTeam = winningTeam, stats = {} })
	self:_fireEvent("RoundOver", winningTeam, self._roundNumber)
	local gameOver = WinConditionEvaluator.isGameOver(self._roundResults, self._roundNumber)
	if gameOver then
		self:_transition(Configs.GAME_STATES.GameOver)
	else
		self:_transition(Configs.GAME_STATES.RoundIntermission)
	end
end

function RoundSystem:_fireEvent(event: string, ...: any)
	local list = self._listeners[event]
	if not list then return end
	local args = { ... }
	for _, fn in list do
		task.spawn(fn, table.unpack(args))
	end
end

function RoundSystem:_broadcastUpdate()
	if self._destroyed then return end
	self._broadcastRemote:FireAllClients(self:GetSnapshot())
end

return RoundSystem
