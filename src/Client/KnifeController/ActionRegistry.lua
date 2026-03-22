local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local StabAction = require(script.Parent.Actions.StabAction)
local ThrowAction = require(script.Parent.Actions.ThrowAction)

return createRegistry({ StabAction, ThrowAction })
