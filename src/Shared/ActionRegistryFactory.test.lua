local createRegistry = require(script.Parent.ActionRegistryFactory)

local first = { name = "Dash", marker = "first" }
local duplicate = { name = "Dash", marker = "duplicate" }
local second = { name = "Block", marker = "second" }

local registry = createRegistry({ first, duplicate, second })

assert(registry.getAction("Dash") == first, "duplicate action does not replace the first registration")
assert(registry.getAction("Block") == second, "registry returns later unique actions")
assert(registry.getAction("Missing") == nil, "missing action returns nil")

print("[ActionRegistryFactory.test] passed")
return true
