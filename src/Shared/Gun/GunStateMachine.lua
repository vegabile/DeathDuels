local Types = require(script.Parent.Types)

local GunStateMachine = {}

function GunStateMachine.new(): Types.GunStateMachine
	return {
		isShooting = false,
	}
end

function GunStateMachine.isLocked(state: Types.GunStateMachine): boolean
	return state.isShooting
end

function GunStateMachine.setActionActive(state: Types.GunStateMachine, actionName: string): boolean
	if state.isShooting then
		return false
	end

	if actionName == "Shoot" then
		state.isShooting = true
	else
		warn(`[GunStateMachine] Unknown action: {actionName}`)
		return false
	end

	return true
end

function GunStateMachine.resetAction(state: Types.GunStateMachine, actionName: string)
	if actionName == "Shoot" then
		state.isShooting = false
	else
		warn(`[GunStateMachine] Unknown action to reset: {actionName}`)
	end
end

function GunStateMachine.resetAll(state: Types.GunStateMachine)
	state.isShooting = false
end

function GunStateMachine.serialize(state: Types.GunStateMachine): Types.GunStateMachine
	return {
		isShooting = state.isShooting,
	}
end

return GunStateMachine
