local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

--// Powers/ is empty in v1; follow-up features add entries here as { Power1, Power2, ... }.
local base = createRegistry({})

local PowerRegistry = {}

function PowerRegistry.getPower(name: string)
	return base.getAction(name)
end

return PowerRegistry
