local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)
local PayloadValidator = require(ReplicatedStorage.Gun.PayloadValidator)
local GunUtility = require(ReplicatedStorage.Gun.GunUtility)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local ServerTypes = require(script.Types)
local ServerConfigs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)

local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local GunService = {}

local currentRoundState: string = ""
ServerEventBus:Connect("RoundStateChanged", function(newState: string)
	currentRoundState = newState
end, { replayLast = true })

local playerStates: { [Player]: ServerTypes.PlayerGunState } = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isPlayerCombatEligible(player: Player): boolean
	if player:GetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE) ~= true then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and isFiniteNumber(humanoid.Health) and humanoid.Health > 0
end

function GunService._getRemoteName(player: Player): string
	return `GunAction_{player.UserId}`
end

function GunService.OnPlayerAdded(player: Player)
	debugPrint(DEBUG, `[GunService] OnPlayerAdded for {player.Name}`)

	local remoteName = GunService._getRemoteName(player)
	NetworkRouter:CreateRemoteEvent(remoteName)

	local state: ServerTypes.PlayerGunState = {
		stateMachine = GunStateMachine.new(),
		remote = NetworkRouter:Get(remoteName),
		connections = {},
		lastActionTimestamp = 0,
	}

	local listenConnection = NetworkRouter:Listen(remoteName, function(firingPlayer, payload)
		if firingPlayer ~= player then
			warn(`[GunService] Remote spoofing detected: {firingPlayer.Name} on {player.Name}'s remote`)
			return
		end
		GunService._handleActionRequest(player, payload)
	end)

	table.insert(state.connections, listenConnection)
	playerStates[player] = state
end

function GunService.OnPlayerRemoving(player: Player)
	debugPrint(DEBUG, `[GunService] OnPlayerRemoving for {player.Name}`)

	local state = playerStates[player]
	if not state then return end

	for _, conn in state.connections do
		conn:Disconnect()
	end

	NetworkRouter:Remove(GunService._getRemoteName(player))
	state.remote:Destroy()
	playerStates[player] = nil
end

function GunService.OnPlayerDied(player: Player)
	local state = playerStates[player]
	if not state then return end

	GunStateMachine.resetAll(state.stateMachine)
	state.lastActionTimestamp = 0
end

function GunService._hasGunEquipped(player: Player): boolean
	return GunUtility.findGunTool(player.Character) ~= nil
end

function GunService._handleActionRequest(player: Player, payload: any)
	local state = playerStates[player]
	local sequenceId = PayloadValidator.sanitizeSequenceId(payload)

	if not state then
		warn(`[GunService] No state for {player.Name}`)
		return
	end

	if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
		warn(`[GunService] Action rejected: round state is {currentRoundState}`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	if player:GetAttribute("CombatDisabled") then
		warn(`[GunService] CombatDisabled on {player.Name} — rejecting action`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	local valid, reason = PayloadValidator.validate(payload)
	if not valid then
		warn(`[GunService] Invalid payload from {player.Name}: {reason}`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	if not isPlayerCombatEligible(player) then
		warn(`[GunService] {player.Name} is not combat eligible`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	if not GunService._hasGunEquipped(player) then
		warn(`[GunService] {player.Name} has no gun equipped`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	local action = ActionRegistry.getAction(payload.desiredAction)
	if not action then
		warn(`[GunService] Unknown action requested: {payload.desiredAction}`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	local gunMult = player:GetAttribute("GunCooldownMult") or 1
	local effectiveCooldown = action.cooldown * gunMult
	local now = tick()
	local timeSinceLast = now - state.lastActionTimestamp
	if timeSinceLast < (effectiveCooldown - ServerConfigs.RATE_LIMIT_BUFFER) then
		warn(`[GunService] Rate limit: {player.Name} ({timeSinceLast}s since last)`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	local accepted = GunStateMachine.setActionActive(state.stateMachine, action.name)
	if not accepted then
		debugPrint(DEBUG, `[GunService] {player.Name} action rejected: state locked`)
		GunService._sendStateOverride(player, state, sequenceId)
		return
	end

	state.lastActionTimestamp = now

	local directionVector = nil
	if payload.directionVector then
		directionVector = PayloadValidator.normalizeDirection(payload.directionVector)
	end

	action.serverExecute(player, state, directionVector, payload.restOrigin)
	player:SetAttribute(RoundConfigs.QUEST_USED_GUN_ATTRIBUTE, true)

	task.delay(effectiveCooldown, function()
		if playerStates[player] ~= state then return end
		GunStateMachine.resetAction(state.stateMachine, action.name)
		NetworkRouter:Call(GunService._getRemoteName(player), player, {
			payloadType = "CooldownReset",
			actionName = action.name,
		})
		debugPrint(DEBUG, `[GunService] Cooldown reset for {player.Name}: {action.name}`)
	end)
end

function GunService._sendStateOverride(player: Player, state: ServerTypes.PlayerGunState, sequenceId: number)
	NetworkRouter:Call(GunService._getRemoteName(player), player, {
		payloadType = "StateOverride",
		sequenceId = sequenceId,
		overriddenState = GunStateMachine.serialize(state.stateMachine),
	})
end

return GunService
