local ReplicatedStorage = game:GetService("ReplicatedStorage")
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)
local Types = require(ReplicatedStorage.Power.Types)

type Power = Types.Power

local powersFolder = script.Parent:FindFirstChild("Powers")
if not powersFolder then
	warn("[PowerRegistry] Powers folder missing — registry will be empty")
end

local powers: { Power } = {}
if powersFolder then
	for _, module in powersFolder:GetChildren() do
		if not module:IsA("ModuleScript") then continue end
		if module.Name:match("%.test$") then continue end
		table.insert(powers, require(module))
	end
end

local base = createRegistry(powers)

local PowerRegistry = {}

function PowerRegistry.getPower(name: string): Power?
	return base.getAction(name)
end

return PowerRegistry
