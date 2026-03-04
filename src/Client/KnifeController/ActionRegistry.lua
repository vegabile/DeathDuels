local StabAction = require(script.Parent.Actions.StabAction)
local ThrowAction = require(script.Parent.Actions.ThrowAction)

local ActionRegistry = {}

local registry: { [string]: any } = {}

local function register(action)
	if registry[action.name] then
		warn(`[ActionRegistry] Duplicate action registration: {action.name}`)
		return
	end
	registry[action.name] = action
end

register(StabAction)
register(ThrowAction)

function ActionRegistry.getAction(name: string)
	local action = registry[name]
	if not action then
		warn(`[ActionRegistry] No action found for: {name}`)
	end
	return action
end

return ActionRegistry
