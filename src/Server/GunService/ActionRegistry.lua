local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local ShootAction = require(script.Parent.Actions.ShootAction)

return createRegistry({ ShootAction })
