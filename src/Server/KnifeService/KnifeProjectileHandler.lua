local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)

local function knifeTrace(message: string)
	print("[KNIFE] " .. message)
end

local KnifeProjectileHandler = {}

local function getOrCreateFolder(name: string): Folder
	local folder = workspace:FindFirstChild(name)
	if not folder then
		knifeTrace(`creating folder {name}`)
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = workspace
	else
		knifeTrace(`found existing folder {name}`)
	end
	return folder
end

function KnifeProjectileHandler.spawnProjectile(
	player: Player,
	directionVector: Vector3,
	projectileTemplate: Instance,
	blacklistedInstancesAndDescendants: { Instance }?,
	onHit: (hitPlayer: Player) -> (),
	spawnCFrameOverride: CFrame?
)
	knifeTrace(`spawnProjectile called for {player.Name}`)
	local character = player.Character
	if not character then
		warn(`[KNIFE] [KnifeProjectileHandler] No character for {player.Name}`)
		return nil
	end
	knifeTrace(`character found for {player.Name}: {character.Name}`)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		knifeTrace(`rootPart missing for {player.Name}`)
		return nil
	end
	knifeTrace(`spawn template={projectileTemplate:GetFullName()} root={rootPart:GetFullName()}`)
	knifeTrace(`incoming direction magnitude={directionVector.Magnitude}`)

	local knifeFolder = getOrCreateFolder("KnifeIgnoreFolder")
	knifeTrace("using KnifeIgnoreFolder for spawned handle")

	local clonedHandle = ProjectileFactory.spawnProjectile({
		template = projectileTemplate,
		directionVector = directionVector,
		spawnCFrame = spawnCFrameOverride or projectileTemplate.Handle.CFrame,
		parent = knifeFolder,
		transparency = 1,
	}, player, blacklistedInstancesAndDescendants, onHit)

	if not clonedHandle then
		warn(`[KNIFE] [KnifeProjectileHandler] ProjectileFactory failed for {player.Name}`)
		return nil
	end
	knifeTrace(`spawned cloned handle {clonedHandle:GetFullName()}`)

	knifeTrace(`ProjectileFactory spawn successful for {player.Name}`)

	return clonedHandle
end

return KnifeProjectileHandler
