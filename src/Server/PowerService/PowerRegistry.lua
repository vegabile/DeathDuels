local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)
local Types = require(ReplicatedStorage.Power.Types)

type Power = Types.Power

--// Powers/ is empty in v1; follow-up features add entries here as { Power1, Power2, ... }.
local base = createRegistry({})

local PowerRegistry = {}

function PowerRegistry.getPower(name: string): Power?
	return base.getAction(name)
end

return PowerRegistry
