local Types = require(script.Parent.Types)

local KnifeStateMachine = {}

function KnifeStateMachine.new(): Types.KnifeStateMachine
	return {
		isStabbing = false,
		isThrowing = false,
	}
end

function KnifeStateMachine.isLocked(state: Types.KnifeStateMachine): boolean
	return state.isStabbing or state.isThrowing
end

--// Returns false if the state machine rejects the transition
function KnifeStateMachine.setActionActive(state: Types.KnifeStateMachine, actionName: string): boolean
	if state.isStabbing or state.isThrowing then
		return false
	end

	if actionName == "Stab" then
		state.isStabbing = true
	elseif actionName == "Throw" then
		state.isThrowing = true
	else
		warn(`[KnifeStateMachine] Unknown action: {actionName}`)
		return false
	end

	return true
end

function KnifeStateMachine.resetAction(state: Types.KnifeStateMachine, actionName: string)
	if actionName == "Stab" then
		state.isStabbing = false
	elseif actionName == "Throw" then
		state.isThrowing = false
	else
		warn(`[KnifeStateMachine] Unknown action to reset: {actionName}`)
	end
end

function KnifeStateMachine.resetAll(state: Types.KnifeStateMachine)
	state.isStabbing = false
	state.isThrowing = false
end

function KnifeStateMachine.serialize(state: Types.KnifeStateMachine): Types.KnifeStateMachine
	return {
		isStabbing = state.isStabbing,
		isThrowing = state.isThrowing,
	}
end

return KnifeStateMachine
