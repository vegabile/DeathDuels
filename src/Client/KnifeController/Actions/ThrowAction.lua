local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration
ThrowAction.animationId = SharedConfigs.ThrowAnimationId

local function findKnifeTool(): Tool?
	local character = Players.LocalPlayer.Character
	if not character then return nil end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			return child
		end
	end
	return nil
end

local function getOrCreateClientFolder(): Folder
	local folderName = "ClientKnifeProjectiles"
	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = workspace
	end
	return folder
end

function ThrowAction.clientExecute(_state, directionVector: Vector3?)
	if not directionVector then return end

	local knifeTool = findKnifeTool()
	if not knifeTool then
		warn("[ThrowAction] No knife tool found for client cosmetic projectile")
		return
	end

	local handle = knifeTool:FindFirstChild("Handle")
	if not handle then return end

	local character = Players.LocalPlayer.Character
	local clientFolder = getOrCreateClientFolder()

	ProjectileFactory.spawnProjectile({
		template = knifeTool,
		directionVector = directionVector,
		spawnCFrame = handle.CFrame,
		parent = clientFolder,
		transparency = 0,
	}, Players.LocalPlayer, { character, clientFolder }, nil)
end

return ThrowAction
