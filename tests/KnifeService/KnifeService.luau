--// Lune-compatible copy of KnifeService logic
--// Uses dependency injection instead of Roblox requires

local KnifeStateMachine = require("../Knife/KnifeStateMachine")
local PayloadValidator = require("../Knife/PayloadValidator")

local KnifeService = {}

function KnifeService.new(deps)
	local self = {}

	local playerStates = {}
	local debugPrint = deps.debugPrint or function() end
	local DEBUG = deps.debugMode or false
	local actionRegistry = deps.actionRegistry or {}
	local hasKnifeEquipped = deps.hasKnifeEquipped or function() return true end
	local sendToClient = deps.sendToClient or function() end
	local getTime = deps.getTime or function() return 0 end
	local rateLimitBuffer = deps.rateLimitBuffer or 0.05

	function self.OnPlayerAdded(player)
		local state = {
			stateMachine = KnifeStateMachine.new(),
			connections = {},
			lastActionTimestamp = 0,
			currentTickConnection = nil,
			alreadyHit = {},
		}
		playerStates[player] = state
	end

	function self.OnPlayerRemoving(player)
		local state = playerStates[player]
		if not state then return end
		playerStates[player] = nil
	end

	function self.OnPlayerDied(player)
		local state = playerStates[player]
		if not state then return end

		KnifeStateMachine.resetAll(state.stateMachine)
		state.alreadyHit = {}
	end

	function self.GetPlayerState(player)
		return playerStates[player]
	end

	function self.HandleActionRequest(player, payload)
		local state = playerStates[player]
		if not state then
			return { rejected = true, reason = "no_state" }
		end

		local valid, reason = PayloadValidator.validate(payload)
		if not valid then
			self._sendStateOverride(player, state, (type(payload) == "table" and payload.sequenceId) or 0)
			return { rejected = true, reason = "invalid_payload", detail = reason }
		end

		if not hasKnifeEquipped(player) then
			self._sendStateOverride(player, state, payload.sequenceId)
			return { rejected = true, reason = "no_knife" }
		end

		local action = actionRegistry[payload.desiredAction]
		if not action then
			return { rejected = true, reason = "unknown_action" }
		end

		local now = getTime()
		local timeSinceLast = now - state.lastActionTimestamp
		if timeSinceLast < (action.cooldown - rateLimitBuffer) then
			self._sendStateOverride(player, state, payload.sequenceId)
			return { rejected = true, reason = "rate_limited" }
		end

		local accepted = KnifeStateMachine.setActionActive(state.stateMachine, action.name)
		if not accepted then
			self._sendStateOverride(player, state, payload.sequenceId)
			return { rejected = true, reason = "state_locked" }
		end

		state.lastActionTimestamp = now

		return { rejected = false, actionName = action.name }
	end

	function self._sendStateOverride(player, state, sequenceId)
		sendToClient(player, {
			payloadType = "StateOverride",
			sequenceId = sequenceId,
			overriddenState = KnifeStateMachine.serialize(state.stateMachine),
		})
	end

	function self.ResetAction(player, actionName)
		local state = playerStates[player]
		if not state then return end
		KnifeStateMachine.resetAction(state.stateMachine, actionName)
		sendToClient(player, {
			payloadType = "CooldownReset",
			actionName = actionName,
		})
	end

	return self
end

return KnifeService
