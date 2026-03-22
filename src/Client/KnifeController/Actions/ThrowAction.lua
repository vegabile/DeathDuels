local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration
ThrowAction.animationId = SharedConfigs.ThrowAnimationId

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

	local knifeTool = KnifeUtility.findKnifeTool(Players.LocalPlayer.Character)
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
