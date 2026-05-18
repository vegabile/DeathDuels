local GunStateMachine = require(script.Parent.GunStateMachine)

local state = GunStateMachine.new()
assert(state.isShooting == false, "new gun state starts idle")
assert(GunStateMachine.isLocked(state) == false, "new gun state is unlocked")

assert(GunStateMachine.setActionActive(state, "Reload") == false, "unknown action is rejected")
assert(GunStateMachine.isLocked(state) == false, "unknown action does not lock state")

assert(GunStateMachine.setActionActive(state, "Shoot") == true, "shoot locks state")
assert(GunStateMachine.isLocked(state) == true, "shooting state is locked")
assert(GunStateMachine.setActionActive(state, "Shoot") == false, "locked state rejects another shoot")

local serialized = GunStateMachine.serialize(state)
assert(serialized.isShooting == true, "serialized state reflects lock")
serialized.isShooting = false
assert(state.isShooting == true, "serialized state is a copy")

GunStateMachine.resetAction(state, "Unknown")
assert(state.isShooting == true, "unknown reset does not unlock")
GunStateMachine.resetAction(state, "Shoot")
assert(GunStateMachine.isLocked(state) == false, "resetAction unlocks shoot")

GunStateMachine.setActionActive(state, "Shoot")
GunStateMachine.resetAll(state)
assert(state.isShooting == false, "resetAll clears shooting")

print("[Gun.GunStateMachine.test] passed")
return true
