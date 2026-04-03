local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponModelValidator = require(ReplicatedStorage.WeaponModelValidator)

local WeaponDistributor = {}

local knifeTemplate: Tool? = nil
local gunTemplate: Tool? = nil

local function ensureKnifeHitbox(tool: Tool)
	if tool:FindFirstChild("Hitbox") then return end

	local handle = tool:FindFirstChild("Handle") :: BasePart
	local bbCFrame, bbSize = tool:GetBoundingBox()

	--// Fall back to Handle dimensions if the bounding box is degenerate
	if bbSize.Magnitude < 0.01 then
		warn("[WeaponDistributor] Knife bounding box is near-zero — falling back to Handle size")
		bbCFrame = handle.CFrame
		bbSize = handle.Size
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = bbSize
	hitbox.CFrame = bbCFrame
	hitbox.CanCollide = false
	hitbox.Transparency = 1
	hitbox.Massless = true
	hitbox.CastShadow = false

	--// Parent before weld so Part0/Part1 are in the same tree
	hitbox.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = hitbox
	weld.Parent = hitbox
end

local function ensureGunShootPoint(tool: Tool)
	local handle = tool:FindFirstChild("Handle") :: BasePart

	if handle:FindFirstChild("ShootPoint") then return end

	--// Common Studio name for the same attachment — just rename it
	local existing = handle:FindFirstChild("ShootAttachment")
	if existing then
		existing.Name = "ShootPoint"
		return
	end

	--// Neither present — create one at the forward face of the Handle
	local shootPoint = Instance.new("Attachment")
	shootPoint.Name = "ShootPoint"
	shootPoint.Position = Vector3.new(0, 0, handle.Size.Z / 2)
	shootPoint.Parent = handle
	warn("[WeaponDistributor] No ShootPoint or ShootAttachment found on gun Handle — created one at Handle front. Verify position in Studio.")
end

function WeaponDistributor.init(knife: any, gun: any): boolean
	local knifeOk, knifeErr = WeaponModelValidator.validateKnife(knife)
	if not knifeOk then
		warn(`[WeaponDistributor] Knife template invalid: {knifeErr}`)
		return false
	end

	local gunOk, gunErr = WeaponModelValidator.validateGun(gun)
	if not gunOk then
		warn(`[WeaponDistributor] Gun template invalid: {gunErr}`)
		return false
	end

	ensureKnifeHitbox(knife)
	ensureGunShootPoint(gun)

	knifeTemplate = knife
	gunTemplate = gun
	return true
end

function WeaponDistributor.distributeToPlayer(player: Player)
	if not knifeTemplate or not gunTemplate then
		warn(`[WeaponDistributor] Cannot distribute to {player.Name} — not initialized`)
		return
	end

	local backpack = player:FindFirstChildWhichIsA("Backpack")
	if not backpack then
		warn(`[WeaponDistributor] No Backpack found for {player.Name}`)
		return
	end

	local knife = knifeTemplate:Clone()
	knife:SetAttribute("IsKnife", true)
	knife.Parent = backpack

	local gun = gunTemplate:Clone()
	gun:SetAttribute("IsGun", true)
	gun.Parent = backpack
end

--// Test-only: resets module state so tests can run in isolation
function WeaponDistributor._reset()
	knifeTemplate = nil
	gunTemplate = nil
end

return WeaponDistributor
