local function createRegistry(actions: { any })
	local registry: { [string]: any } = {}

	for _, action in actions do
		if registry[action.name] then
			warn(`[ActionRegistry] Duplicate action registration: {action.name}`)
			continue
		end
		registry[action.name] = action
	end

	local ActionRegistry = {}

	function ActionRegistry.getAction(name: string)
		local action = registry[name]
		if not action then
			warn(`[ActionRegistry] No action found for: {name}`)
		end
		return action
	end

	return ActionRegistry
end

return createRegistry
