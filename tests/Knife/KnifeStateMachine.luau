local KnifeStateMachine = {}

function KnifeStateMachine.new()
	return {
		isStabbing = false,
		isThrowing = false,
	}
end

function KnifeStateMachine.isLocked(state)
	return state.isStabbing or state.isThrowing
end

function KnifeStateMachine.setActionActive(state, actionName)
	if state.isStabbing or state.isThrowing then
		return false
	end

	if actionName == "Stab" then
		state.isStabbing = true
	elseif actionName == "Throw" then
		state.isThrowing = true
	else
		return false
	end

	return true
end

function KnifeStateMachine.resetAction(state, actionName)
	if actionName == "Stab" then
		state.isStabbing = false
	elseif actionName == "Throw" then
		state.isThrowing = false
	end
end

function KnifeStateMachine.resetAll(state)
	state.isStabbing = false
	state.isThrowing = false
end

function KnifeStateMachine.serialize(state)
	return {
		isStabbing = state.isStabbing,
		isThrowing = state.isThrowing,
	}
end

return KnifeStateMachine
