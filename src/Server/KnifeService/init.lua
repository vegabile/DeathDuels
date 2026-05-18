local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)
local PayloadValidator = require(ReplicatedStorage.Knife.PayloadValidator)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local ServerTypes = require(script.Types)
local ServerConfigs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)

local function knifeTrace(message: string)
end

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
	knifeTrace(`OnPlayerAdded {player.Name}`)

	local remoteName = KnifeService._getRemoteName(player)
	knifeTrace(`creating remote {remoteName}`)
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
			warn(`[KNIFE] [KnifeService] Remote spoofing detected: {firingPlayer.Name} on {player.Name}'s remote`)
			return
		end
		KnifeService._handleActionRequest(player, payload)
	end)

	table.insert(state.connections, listenConnection)
	playerStates[player] = state
end

function KnifeService.OnPlayerRemoving(player: Player)
	knifeTrace(`OnPlayerRemoving {player.Name}`)

	local state = playerStates[player]
	if not state then return end

	for _, conn in state.connections do
		conn:Disconnect()
	end

	if state.currentTickConnection then
		state.currentTickConnection:Disconnect()
	end

	NetworkRouter:Remove(KnifeService._getRemoteName(player))
	state.remote:Destroy()
	playerStates[player] = nil
end

function KnifeService.OnPlayerDied(player: Player)
	knifeTrace(`OnPlayerDied {player.Name}`)
	local state = playerStates[player]
	if not state then return end

	KnifeStateMachine.resetAll(state.stateMachine)
	state.lastActionTimestamp = 0

	if state.currentTickConnection then
		state.currentTickConnection:Disconnect()
		state.currentTickConnection = nil
	end
	if state.stabTouchedConn then
		state.stabTouchedConn:Disconnect()
		state.stabTouchedConn = nil
	end
	state.alreadyHit = {}
end

function KnifeService._hasKnifeEquipped(player: Player): boolean
	return KnifeUtility.findKnifeTool(player.Character) ~= nil
end

function KnifeService._handleActionRequest(player: Player, payload: any)
	knifeTrace(`_handleActionRequest from {player.Name}`)
	knifeTrace(`currentRoundState={currentRoundState}`)
	if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
		warn(`[KNIFE] [KnifeService] Action rejected: round state is {currentRoundState}`)
		return
	end

	if player:GetAttribute("CombatDisabled") then
		warn(`[KNIFE] [KnifeService] CombatDisabled on {player.Name} — rejecting action`)
		local state = playerStates[player]
		if state then KnifeService._sendStateOverride(player, state, (payload and payload.sequenceId) or 0) end
		return
	end

	local state = playerStates[player]
	if not state then
		warn(`[KNIFE] [KnifeService] No state for {player.Name}`)
		return
	end

	knifeTrace(`payload for {player.Name}: desired={payload and payload.desiredAction} seq={payload and payload.sequenceId}`)
	local valid, reason = PayloadValidator.validate(payload)
	if not valid then
		warn(`[KNIFE] [KnifeService] Invalid payload from {player.Name}: {reason}`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId or 0)
		return
	end

	if not KnifeService._hasKnifeEquipped(player) then
		warn(`[KNIFE] [KnifeService] {player.Name} has no knife equipped`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId)
		return
	end

	local action = ActionRegistry.getAction(payload.desiredAction)
	if not action then
		knifeTrace(`unknown action requested: {payload.desiredAction}`)
		return
	end
	knifeTrace(`resolved action={action.name}`)

	local knifeMult = player:GetAttribute("KnifeCooldownMult") or 1
	local effectiveCooldown = action.cooldown * knifeMult
	local now = tick()
	local timeSinceLast = now - state.lastActionTimestamp
	if timeSinceLast < (effectiveCooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
		warn(`[KNIFE] [KnifeService] Rate limit: {player.Name} ({timeSinceLast}s since last)`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId)
		return
	end

	local accepted = KnifeStateMachine.setActionActive(state.stateMachine, action.name)
	if not accepted then
		knifeTrace(`action rejected by state machine: {player.Name}`)
		KnifeService._sendStateOverride(player, state, payload.sequenceId)
		return
	end

	state.lastActionTimestamp = now
	knifeTrace(`state lock set + timestamp updated for {action.name}`)

	local directionVector = nil
	if payload.directionVector then
		directionVector = PayloadValidator.normalizeDirection(payload.directionVector)
	end

	action.serverExecute(player, state, directionVector, payload.restOrigin, payload.spawnCFrame)
	knifeTrace(`serverExecute called for {action.name} by {player.Name}`)

	task.delay(effectiveCooldown, function()
		if playerStates[player] ~= state then return end
		KnifeStateMachine.resetAction(state.stateMachine, action.name)
		NetworkRouter:Call(KnifeService._getRemoteName(player), player, {
			payloadType = "CooldownReset",
			actionName = action.name,
		})
		knifeTrace(`cooldown reset sent for {player.Name}:{action.name}`)
	end)
end

function KnifeService._sendStateOverride(player: Player, state: ServerTypes.PlayerKnifeState, sequenceId: number)
	knifeTrace(`send StateOverride {player.Name} seq={sequenceId}`)
	NetworkRouter:Call(KnifeService._getRemoteName(player), player, {
		payloadType = "StateOverride",
		sequenceId = sequenceId,
		overriddenState = KnifeStateMachine.serialize(state.stateMachine),
	})
end

return KnifeService
