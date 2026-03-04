local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)

local DEBUG = true
local debugPrint = DebugUtility.Print

local KnifeProjectileHandler = {}

local function getOrCreateFolder(name: string): Folder
	local folder = workspace:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = workspace
	end
	return folder
end

function KnifeProjectileHandler.spawnProjectile(
	player: Player,
	directionVector: Vector3,
	projectileTemplate: Instance,
	blacklistedInstancesAndDescendants: { Instance }?,
	onHit: (hitPlayer: Player) -> ()
)
	local character = player.Character
	if not character then
		warn(`[KnifeProjectileHandler] No character for {player.Name}`)
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		warn(`[KnifeProjectileHandler] No HumanoidRootPart for {player.Name}`)
		return nil
	end

	local knifeFolder = getOrCreateFolder("KnifeIgnoreFolder")

	local clonedHandle = ProjectileFactory.spawnProjectile({
		template = projectileTemplate,
		directionVector = directionVector,
		spawnCFrame = projectileTemplate.Handle.CFrame,
		parent = knifeFolder,
		transparency = 1,
	}, player, blacklistedInstancesAndDescendants, onHit)

	if not clonedHandle then
		warn(`[KnifeProjectileHandler] ProjectileFactory failed for {player.Name}`)
		return nil
	end

	debugPrint(DEBUG, `[KnifeProjectileHandler] Spawned projectile for {player.Name}`)

	return clonedHandle
end

return KnifeProjectileHandler
