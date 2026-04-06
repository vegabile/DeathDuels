local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)
local PayloadValidator = require(ReplicatedStorage.Knife.PayloadValidator)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local ServerTypes = require(script.Types)
local ServerConfigs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)

local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local KnifeService = {}

local currentRoundState: string = ""
ServerEventBus:Connect("RoundStateChanged", function(newState: string)
	currentRoundState = newState
end)

local playerStates: { [Player]: ServerTypes.PlayerKnifeState } = {}

function KnifeService._getRemoteName(player: Player): string
	return `KnifeAction_{player.UserId}`
end

function KnifeService.OnPlayerAdded(player: Player)
	debugPrint(DEBUG, `[KnifeService] OnPlayerAdded for {player.Name}`)

	local remoteName = KnifeService._getRemoteName(player)
	NetworkRouter:CreateRemoteEvent(remoteName)

	local state: ServerTypes.PlayerKnifeState = {
		stateMachine = KnifeStateMachine.new(),
		remote = NetworkRouter:Get(remoteName),
		connections = {},
		lastActionTimestamp = 0,
		currentTickConnection = nil,
		alreadyHit = {},
	}

	local listenConnection = NetworkRouter:Listen(remoteName, function(firingPlayer, payload)
		if firingPlayer ~= player then
			warn(`[KnifeService] Remote spoofing detected: {firingPlayer.Name} on {player.Name}'s remote`)
			return
		end
		KnifeService._handleActionRequest(player, payload)
	end)

	table.insert(state.connections, listenConnection)
	playerStates[player] = state
end

function KnifeService.OnPlayerRemoving(player: Player)
	debugPrint(DEBUG, `[KnifeService] OnPlayerRemoving for {player.Name}`)

	local state = playerStates[player]
	if not state then return end

	for _, conn in state.connections do
		conn:Disconnect()
	end

	if state.currentTickConnection then
		state.currentTickConnection:Disconnect()
	end

	state.remote:Destroy()
	playerStates[player] = nil
end

function KnifeService.OnPlayerDied(player: Player)
	local state = playerStates[player]
	if not state then return end

	KnifeStateMachine.resetAll(state.stateMachine)
	state.lastActionTimestamp = 0

	if state.currentTickConnection then
		state.currentTickConnection:Disconnect()
		state.currentTickConnection = nil
	end
	state.alreadyHit = {}
end

function KnifeService._hasKnifeEquipped(player: Player): boolean
	return KnifeUtility.findKnifeTool(player.Character) ~= nil
end

function KnifeService._handleActionRequest(player: Player, payload: any)
	if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
		warn(`[KnifeService] Action rejected: round state is {currentRoundState}`)
		return
	end

	local state = playerStates[player]
	if not state then
		warn(`[KnifeService] No state for {player.Name}`)
		return
	end

	local valid, reason = PayloadValidator.validate(payload)
	if not valid then
		warn(`[KnifeService] Invalid payload from {player.Name}: {reason}`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId or 0)
		return
	end

	if not KnifeService._hasKnifeEquipped(player) then
		warn(`[KnifeService] {player.Name} has no knife equipped`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId)
		return
	end

	local action = ActionRegistry.getAction(payload.desiredAction)
	if not action then return end

	local now = tick()
	local timeSinceLast = now - state.lastActionTimestamp
	if timeSinceLast < (action.cooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
		warn(`[KnifeService] Rate limit: {player.Name} ({timeSinceLast}s since last)`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId)
		return
	end

	local accepted = KnifeStateMachine.setActionActive(state.stateMachine, action.name)
	if not accepted then
		debugPrint(DEBUG, `[KnifeService] {player.Name} action rejected: state locked`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId)
		return
	end

	state.lastActionTimestamp = now

	local directionVector = nil
	if payload.directionVector then
		directionVector = PayloadValidator.normalizeDirection(payload.directionVector)
	end

	action.serverExecute(player, state, directionVector)

	task.delay(action.cooldown, function()
		if playerStates[player] ~= state then return end
		KnifeStateMachine.resetAction(state.stateMachine, action.name)
		NetworkRouter:Call(KnifeService._getRemoteName(player), player, {
			payloadType = "CooldownReset",
			actionName = action.name,
		})
		debugPrint(DEBUG, `[KnifeService] Cooldown reset for {player.Name}: {action.name}`)
	end)
end

function KnifeService._sendStateOverride(player: Player, state: ServerTypes.PlayerKnifeState, sequenceId: number)
	NetworkRouter:Call(KnifeService._getRemoteName(player), player, {
		payloadType = "StateOverride",
		sequenceId = sequenceId,
		overriddenState = KnifeStateMachine.serialize(state.stateMachine),
	})
end

return KnifeService
