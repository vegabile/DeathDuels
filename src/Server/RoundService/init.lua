local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configs = require(ReplicatedStorage.Round.Configs)
local SharedPowerConfigs = require(ReplicatedStorage.Power.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local RoundStateMachine = require(script.RoundStateMachine)
local WinConditionEvaluator = require(script.WinConditionEvaluator)
local RoundOrchestrator = require(script.RoundOrchestrator)

local Types = require(ReplicatedStorage.Round.Types)
type TeleportMetadata = Types.TeleportMetadata

local TeleportMetadataService = require(script.TeleportMetadataService)
local PlayerReadiness = require(script.PlayerReadiness)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local ReconnectService = require(ServerScriptService.ReconnectService)
local PowerService = require(ServerScriptService.PowerService)

local RoundSystem = {}
RoundSystem.__index = RoundSystem

local function setPowerRoundEligible(player: Player, eligible: boolean)
	player:SetAttribute(SharedPowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE, eligible)
	player:SetAttribute(Configs.COMBAT_ELIGIBLE_ATTRIBUTE, eligible)
end

local function isTeamFullyDisconnected(teamSnapshot): boolean
	if not teamSnapshot then
		return false
	end
	if (teamSnapshot.originalPlayerCount or 0) <= 0 then
		return false
	end
	return teamSnapshot.disconnectedPlayers >= teamSnapshot.originalPlayerCount
end

local function isMatchEndedState(state: string): boolean
	return state == Configs.GAME_STATES.GameOver
		or state == Configs.GAME_STATES.TeleportingOut
		or state == Configs.GAME_STATES.Aborted
end

local function replacePlayerInList(players: { Player }, userId: number, oldPlayer: Player?, newPlayer: Player): boolean
	for i, existing in players do
		if existing == oldPlayer or existing.UserId == userId then
			players[i] = newPlayer
			return true
		end
	end
	return false
end

local function normalizeTicketLoadout(ticket: any)
	if type(ticket) ~= "table" or type(ticket.loadout) ~= "table" then
		return nil
	end
	return ticket.loadout
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
	self._playerStatesByUserId = {} :: { [number]: any }
	self._playersByUserId = {} :: { [number]: Player }
	self._roundResults = {}
	self._disconnectedStats = {} :: { [string]: any }
	self._listeners = {} :: { [string]: { (...any) -> () } }
	self._roundToken = 0
	self._broadcastRemote = NetworkRouter:CreateRemoteEvent("RoundUpdate")
	self._snapshotRemote = NetworkRouter:CreateRemoteFunction("RoundGetSnapshot")
	self._waitTask = nil
	self._roundTimerTask = nil
	self._mapModel = nil
	self._destroyed = false
	self._positioningPlayers = false
	self._matchEnded = false

	NetworkRouter:Listen("RoundGetSnapshot", function(_player: Player)
		if self._destroyed then
			return nil
		end
		return self:GetSnapshot()
	end)

	self._stateMachine:SetTransitionCallback(function(from: string, to: string)
		self:_onStateChanged(from, to)
	end)

	ReconnectService.RegisterMatch(metadata)
	ServerEventBus:FireSticky("RoundStateChanged", Configs.GAME_STATES.WaitingForPlayers)
	RoundOrchestrator.enter(Configs.GAME_STATES.WaitingForPlayers, self)

	return self
end

function RoundSystem:RegisterPlayer(player: Player)
	if self._stateMachine:GetState() ~= Configs.GAME_STATES.WaitingForPlayers then
		warn(`[RoundSystem] RegisterPlayer called outside WaitingForPlayers for {player.Name}`)
		return
	end
	local hasProductionRoster = type(self._metadata.matchId) == "string" and self._metadata.matchId ~= ""
	if hasProductionRoster and not self:ContainsExpectedUserId(player.UserId) then
		warn(`[RoundSystem] RegisterPlayer rejected non-roster userId {player.UserId}`)
		return
	end
	if self._playersByUserId[player.UserId] then
		warn(`[RoundSystem] RegisterPlayer skipped duplicate userId {player.UserId}`)
		return
	end
	for _, pending in self._pendingPlayers do
		if pending.UserId == player.UserId then
			warn(`[RoundSystem] RegisterPlayer skipped duplicate pending userId {player.UserId}`)
			return
		end
	end
	setPowerRoundEligible(player, false)
	table.insert(self._pendingPlayers, player)
	self:_broadcastUpdate()
	if #self._pendingPlayers >= self._expectedPlayerCount then
		self:_transition(Configs.GAME_STATES.AssigningTeams)
	end
end

function RoundSystem:UnregisterPlayer(player: Player)
	setPowerRoundEligible(player, false)
	local state = self._stateMachine:GetState()

	if state == Configs.GAME_STATES.WaitingForPlayers then
		local index = table.find(self._pendingPlayers, player)
		if index then table.remove(self._pendingPlayers, index) end
		self:_broadcastUpdate()
		return
	end

	
	
	
	local playerState = self._playerStates[player]
	if playerState then
		playerState.status = Configs.PLAYER_STATUSES.Disconnected
		playerState:SetInGame(false)
		self._disconnectedStats[tostring(player.UserId)] = playerState:Serialize()
		if not self:IsMatchEnded() then
			local loadout = TeleportMetadataService.GetLoadout(player.UserId)
			ReconnectService.WriteDisconnectTicket(self._metadata, player, playerState, loadout)
		end
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
	setPowerRoundEligible(player, false)
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
	playerState:SetMatchStat("deaths", playerState:GetMatchStat("deaths") + 1)

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local killerUserId = humanoid and humanoid:GetAttribute("LastDamageSource")
	if killerUserId then
		local killer = Players:GetPlayerByUserId(killerUserId)
		local killerState = killer and self._playerStates[killer]
		if killerState then
			killerState:SetStat("kills", killerState:GetStat("kills") + 1)
			killerState:SetMatchStat("kills", killerState:GetMatchStat("kills") + 1)
		end
	end

	self:_fireEvent("PlayerStatusChanged", player, Configs.PLAYER_STATUSES.Dead)
	self:_broadcastUpdate()
	self:_checkWinCondition()
end

function RoundSystem:GetState(): string
	return self._stateMachine:GetState()
end

function RoundSystem:GetMatchId(): string?
	return self._metadata and self._metadata.matchId
end

function RoundSystem:ContainsExpectedUserId(userId: number): boolean
	if type(userId) ~= "number" then
		return false
	end
	for _, entry in self._metadata.teamOnePlayers do
		if entry.UserId == userId then
			return true
		end
	end
	for _, entry in self._metadata.teamTwoPlayers do
		if entry.UserId == userId then
			return true
		end
	end
	return false
end

function RoundSystem:IsMatchEnded(): boolean
	return self._matchEnded or isMatchEndedState(self._stateMachine:GetState())
end

function RoundSystem:MarkMatchEnded()
	if self._matchEnded then return end
	self._matchEnded = true
	ReconnectService.MarkMatchEnded(self._metadata)
end

function RoundSystem:RegisterReconnect(player: Player, ticket: any): (boolean, string?)
	if self:IsMatchEnded() then
		return false, "match-ended"
	end

	setPowerRoundEligible(player, false)
	local userId = player.UserId
	local playerState = self._playerStatesByUserId[userId]
	if not playerState then
		warn(`[RoundSystem] Reconnect rejected for {player.Name}: no participant state for userId {userId}`)
		return false, "participant-not-found"
	end

	local oldPlayer = self._playersByUserId[userId] or playerState.player
	if oldPlayer and oldPlayer ~= player then
		self._playerStates[oldPlayer] = nil
	end

	local team = if type(ticket) == "table" and type(ticket.team) == "number" then ticket.team else playerState.team
	playerState.team = team
	playerState.player = player
	playerState.isInGame = false
	playerState.positionedThisRound = false

	self._playerStates[player] = playerState
	self._playersByUserId[userId] = player
	self._playerStatesByUserId[userId] = playerState
	self._disconnectedStats[tostring(userId)] = nil

	replacePlayerInList(self._roundRoster, userId, oldPlayer, player)
	replacePlayerInList(self._teamPlayers[1], userId, oldPlayer, player)
	replacePlayerInList(self._teamPlayers[2], userId, oldPlayer, player)
	TeleportMetadataService.SetTeam(userId, team)

	local loadout = normalizeTicketLoadout(ticket) or TeleportMetadataService.GetLoadout(userId)
	if loadout then
		TeleportMetadataService.SetLoadout(userId, loadout)
		PowerService.AssignLoadout(player, loadout)
	end
	PlayerReadiness.recordFact(player, "LoadoutResolved")

	local applied = false
	local characterConnection: RBXScriptConnection? = nil
	local function applySpectatorState()
		if applied then return end
		applied = true
		if characterConnection then
			characterConnection:Disconnect()
			characterConnection = nil
		end
		playerState.isInGame = false
		RoundOrchestrator.ApplySkipped(self, player, playerState)
		playerState.isInGame = false
		self:_fireEvent("PlayerStatusChanged", player, Configs.PLAYER_STATUSES.Skipped)
		self:_broadcastUpdate()
	end

	if player.Character then
		applySpectatorState()
	else
		characterConnection = player.CharacterAdded:Connect(function()
			task.defer(applySpectatorState)
		end)
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			warn(`[RoundSystem] Reconnect LoadCharacter failed for {player.Name}: {err}`)
			applySpectatorState()
		end
		task.delay(Configs.CHAR_FACT_WAIT_TIMEOUT, applySpectatorState)
	end

	return true, nil
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
	self:MarkMatchEnded()
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
	local isValid = self._stateMachine:ValidateTransition(to)
	if not isValid then
		return
	end
	if to == Configs.GAME_STATES.RoundActive then
		self._roundNumber += 1
		self._roundToken += 1
	end
	self._stateMachine:Transition(to)
end

function RoundSystem:_onStateChanged(from: string, to: string)
	self:_fireEvent("StateChanged", from, to)
	ServerEventBus:FireSticky("RoundStateChanged", to)
	if to ~= Configs.GAME_STATES.RoundActive then
		for _, playerState in self._playerStates do
			setPowerRoundEligible(playerState.player, false)
		end
	end
	self:_broadcastUpdate()
	if isMatchEndedState(to) then
		self:MarkMatchEnded()
	end
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
