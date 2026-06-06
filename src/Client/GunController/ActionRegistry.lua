local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)

local ShootAction = require(script.Parent.Actions.ShootAction)
local ReloadAction = require(script.Parent.Actions.ReloadAction)

return createRegistry({ ShootAction, ReloadAction })
