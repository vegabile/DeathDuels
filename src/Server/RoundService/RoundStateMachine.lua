local Configs = require(script.Parent.Parent.Parent.Shared.Round.Configs)

local RoundStateMachine = {}
RoundStateMachine.__index = RoundStateMachine

function RoundStateMachine.new()
	return setmetatable({
		currentState = Configs.GAME_STATES.WaitingForPlayers,
	}, RoundStateMachine)
end

function RoundStateMachine:GetState(): string
	return self.currentState
end

function RoundStateMachine:ValidateTransition(to: string): (boolean, string?)
	local valid = Configs.LEGAL_TRANSITIONS[self.currentState]
	if not valid then
		warn(`[RoundStateMachine] Unknown state: {self.currentState}`)
		return false, `Unknown state: {self.currentState}`
	end

	for _, allowed in valid do
		if allowed == to then
			return true, nil
		end
	end

	return false, `Illegal transition: {self.currentState} -> {to}`
end

function RoundStateMachine:Transition(to: string): (boolean, string?)
	local isValid, reason = self:ValidateTransition(to)
	if not isValid then
		warn(`[RoundStateMachine] {reason}`)
		return false, reason
	end

	self.currentState = to
	return true, nil
end

function RoundStateMachine:GetValidTransitions(): { string }
	return Configs.LEGAL_TRANSITIONS[self.currentState] or {}
end

return RoundStateMachine
