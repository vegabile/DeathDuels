local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DebugUtility = require(ReplicatedStorage.DebugUtility)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

--[[
	Builds a complete weapon service from weapon-specific configuration.

	config fields:
	  serviceName        string          Used in log/warn messages.
	  remotePrefix       string          Per-player remote name prefix (e.g. "GunAction").
	  stateMachineModule module          Must expose: new, setActionActive, resetAction, resetAll, serialize.
	  payloadValidatorModule module      Must expose: validate, normalizeDirection.
	  findWeaponTool     function(character) -> Instance?  Returns the equipped weapon tool or nil.
	  actionRegistryModule module        Must expose: getAction.
	  serverConfigs      module          Must expose: DEBUG_MODE, RATE_LIMIT_BUFFER.
	  extraState         function() -> table   (optional) Extra fields merged into the initial player state.
	  onDied             function(state)       (optional) Called after StateMachine.resetAll on player death.
	  onRemoving         function(state)       (optional) Called before the remote is destroyed on player leave.
]]
local function createWeaponService(config)
	local serviceName = config.serviceName
	local remotePrefix = config.remotePrefix
	local StateMachine = config.stateMachineModule
	local PayloadValidator = config.payloadValidatorModule
	local findWeaponTool = config.findWeaponTool
	local ActionRegistry = config.actionRegistryModule
	local ServerConfigs = config.serverConfigs
	local DEBUG = ServerConfigs.DEBUG_MODE
	local debugPrint = DebugUtility.Print

	local Service = {}

	local currentRoundState: string = ""
	ServerEventBus:Connect("RoundStateChanged", function(newState: string)
		currentRoundState = newState
	end)

	local playerStates: { [Player]: any } = {}

	local function getRemoteName(player: Player): string
		return `{remotePrefix}_{player.UserId}`
	end

	function Service.OnPlayerAdded(player: Player)
		debugPrint(DEBUG, `[{serviceName}] OnPlayerAdded for {player.Name}`)

		local remoteName = getRemoteName(player)
		NetworkRouter:CreateRemoteEvent(remoteName)

		local state = {
			stateMachine = StateMachine.new(),
			remote = NetworkRouter:Get(remoteName),
			connections = {},
			lastActionTimestamp = 0,
		}

		if config.extraState then
			for k, v in config.extraState() do
				state[k] = v
			end
		end

		local listenConnection = NetworkRouter:Listen(remoteName, function(firingPlayer, payload)
			if firingPlayer ~= player then
				warn(`[{serviceName}] Remote spoofing detected: {firingPlayer.Name} on {player.Name}'s remote`)
				return
			end
			Service._handleActionRequest(player, payload)
		end)

		table.insert(state.connections, listenConnection)
		playerStates[player] = state
	end

	function Service.OnPlayerRemoving(player: Player)
		debugPrint(DEBUG, `[{serviceName}] OnPlayerRemoving for {player.Name}`)

		local state = playerStates[player]
		if not state then return end

		for _, conn in state.connections do
			conn:Disconnect()
		end

		if config.onRemoving then
			config.onRemoving(state)
		end

		NetworkRouter:Remove(getRemoteName(player))
		state.remote:Destroy()
		playerStates[player] = nil
	end

	function Service.OnPlayerDied(player: Player)
		local state = playerStates[player]
		if not state then return end

		StateMachine.resetAll(state.stateMachine)
		state.lastActionTimestamp = 0

		if config.onDied then
			config.onDied(state)
		end
	end

	function Service._handleActionRequest(player: Player, payload: any)
		if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
			warn(`[{serviceName}] Action rejected: round state is {currentRoundState}`)
			return
		end

		local state = playerStates[player]
		if not state then
			warn(`[{serviceName}] No state for {player.Name}`)
			return
		end

		local valid, reason = PayloadValidator.validate(payload)
		if not valid then
			warn(`[{serviceName}] Invalid payload from {player.Name}: {reason}`)
			Service._sendStateOverride(player, state, payload.sequenceId or 0)
			return
		end

		if not findWeaponTool(player.Character) then
			warn(`[{serviceName}] {player.Name} has no weapon equipped`)
			Service._sendStateOverride(player, state, payload.sequenceId)
			return
		end

		local action = ActionRegistry.getAction(payload.desiredAction)
		if not action then return end

		local now = tick()
		local timeSinceLast = now - state.lastActionTimestamp
		if timeSinceLast < (action.cooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
			warn(`[{serviceName}] Rate limit: {player.Name} ({timeSinceLast}s since last)`)
			Service._sendStateOverride(player, state, payload.sequenceId)
			return
		end

		local accepted = StateMachine.setActionActive(state.stateMachine, action.name)
		if not accepted then
			debugPrint(DEBUG, `[{serviceName}] {player.Name} action rejected: state locked`)
			Service._sendStateOverride(player, state, payload.sequenceId)
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
			StateMachine.resetAction(state.stateMachine, action.name)
			NetworkRouter:Call(getRemoteName(player), player, {
				payloadType = "CooldownReset",
				actionName = action.name,
			})
			debugPrint(DEBUG, `[{serviceName}] Cooldown reset for {player.Name}: {action.name}`)
		end)
	end

	function Service._sendStateOverride(player: Player, state: any, sequenceId: number)
		NetworkRouter:Call(getRemoteName(player), player, {
			payloadType = "StateOverride",
			sequenceId = sequenceId,
			overriddenState = StateMachine.serialize(state.stateMachine),
		})
	end

	return Service
end

return createWeaponService
