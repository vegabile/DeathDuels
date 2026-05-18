local KnifeStateMachine = require(script.Parent.KnifeStateMachine)

local state = KnifeStateMachine.new()
assert(state.isStabbing == false and state.isThrowing == false, "new knife state starts idle")
assert(KnifeStateMachine.isLocked(state) == false, "new knife state is unlocked")

assert(KnifeStateMachine.setActionActive(state, "Spin") == false, "unknown action is rejected")
assert(KnifeStateMachine.isLocked(state) == false, "unknown action does not lock")

assert(KnifeStateMachine.setActionActive(state, "Stab") == true, "stab locks state")
assert(KnifeStateMachine.isLocked(state) == true, "stabbing state is locked")
assert(KnifeStateMachine.setActionActive(state, "Throw") == false, "locked stab rejects throw")
KnifeStateMachine.resetAction(state, "Throw")
assert(state.isStabbing == true, "resetting inactive throw leaves stab lock intact")
KnifeStateMachine.resetAction(state, "Stab")
assert(KnifeStateMachine.isLocked(state) == false, "resetting stab unlocks")

assert(KnifeStateMachine.setActionActive(state, "Throw") == true, "throw locks state")
local serialized = KnifeStateMachine.serialize(state)
assert(serialized.isThrowing == true and serialized.isStabbing == false, "serialized state reflects throw")
serialized.isThrowing = false
assert(state.isThrowing == true, "serialized state is a copy")

KnifeStateMachine.resetAll(state)
assert(state.isStabbing == false and state.isThrowing == false, "resetAll clears every lock")

print("[Knife.KnifeStateMachine.test] passed")
return true
