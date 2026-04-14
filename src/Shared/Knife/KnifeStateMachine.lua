local Types = require(script.Parent.Types)

local function debugLine(message: string)
	print("[KNIFE] [StateMachine] " .. message)
end

local KnifeStateMachine = {}

function KnifeStateMachine.new(): Types.KnifeStateMachine
	debugLine("new state machine created")
	return {
		isStabbing = false,
		isThrowing = false,
	}
end

function KnifeStateMachine.isLocked(state: Types.KnifeStateMachine): boolean
	debugLine(`isLocked query -> stab={state.isStabbing} throw={state.isThrowing}`)
	return state.isStabbing or state.isThrowing
end

--// Returns false if the state machine rejects the transition
function KnifeStateMachine.setActionActive(state: Types.KnifeStateMachine, actionName: string): boolean
	debugLine(`setActionActive requested: {actionName} | stab={state.isStabbing} throw={state.isThrowing}`)
	if state.isStabbing or state.isThrowing then
		debugLine(`rejecting {actionName} due to lock`)
		return false
	end

	if actionName == "Stab" then
		state.isStabbing = true
	elseif actionName == "Throw" then
		state.isThrowing = true
	else
		warn(`[KNIFE] [StateMachine] Unknown action: {actionName}`)
		return false
	end
	debugLine(`state after setActionActive: stab={state.isStabbing} throw={state.isThrowing}`)

	return true
end

function KnifeStateMachine.resetAction(state: Types.KnifeStateMachine, actionName: string)
	debugLine(`resetAction requested: {actionName} | stab={state.isStabbing} throw={state.isThrowing}`)
	if actionName == "Stab" then
		state.isStabbing = false
	elseif actionName == "Throw" then
		state.isThrowing = false
	else
		warn(`[KNIFE] [StateMachine] Unknown action to reset: {actionName}`)
	end
	debugLine(`state after resetAction: stab={state.isStabbing} throw={state.isThrowing}`)
end

function KnifeStateMachine.resetAll(state: Types.KnifeStateMachine)
	debugLine(`resetAll from stab={state.isStabbing} throw={state.isThrowing}`)
	state.isStabbing = false
	state.isThrowing = false
	debugLine("resetAll complete")
end

function KnifeStateMachine.serialize(state: Types.KnifeStateMachine): Types.KnifeStateMachine
	debugLine(`serialize state stab={state.isStabbing} throw={state.isThrowing}`)
	return {
		isStabbing = state.isStabbing,
		isThrowing = state.isThrowing,
	}
end

return KnifeStateMachine
