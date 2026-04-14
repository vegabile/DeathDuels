local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponModelValidator = require(ReplicatedStorage.WeaponModelValidator)

local WeaponDistributor = {}

local knifeTemplates: { [string]: Tool } = {}
local defaultKnifeTemplate: Tool? = nil
local gunTemplates: { [string]: Tool } = {}
local defaultGunTemplate: Tool? = nil

local function normalizeKnifeHandle(tool: Tool)
	local h = tool:FindFirstChild("Handle")
	if not h or not h:IsA("BasePart") then
		warn(`[WeaponDistributor] {tool.Name} has no BasePart Handle to normalize`)
		return
	end

	h.Massless = true
	h.CanCollide = false
	h.Anchored = false
end

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

function WeaponDistributor.init(knives: { Tool }, guns: { Tool }): boolean
	if #knives == 0 then
		warn("[WeaponDistributor] No knife templates provided")
		return false
	end
	if #guns == 0 then
		warn("[WeaponDistributor] No gun templates provided")
		return false
	end

	for _, knife in knives do
		local knifeOk, knifeErr = WeaponModelValidator.validateKnife(knife)
		if not knifeOk then
			warn(`[WeaponDistributor] Knife template invalid: {knifeErr}`)
			return false
		end
	end
	for _, gun in guns do
		local gunOk, gunErr = WeaponModelValidator.validateGun(gun)
		if not gunOk then
			warn(`[WeaponDistributor] Gun template invalid: {gunErr}`)
			return false
		end
	end

	for i, knife in knives do
		normalizeKnifeHandle(knife)
		ensureKnifeHitbox(knife)
		knifeTemplates[knife.Name] = knife
		if i == 1 then defaultKnifeTemplate = knife end
	end
	for i, gun in guns do
		ensureGunShootPoint(gun)
		gunTemplates[gun.Name] = gun
		if i == 1 then defaultGunTemplate = gun end
	end
	return true
end

function WeaponDistributor.distributeToPlayer(player: Player, knifeName: string?, gunName: string?)
	if not defaultKnifeTemplate or not defaultGunTemplate then
		warn(`[WeaponDistributor] Cannot distribute to {player.Name} — not initialized`)
		return
	end

	local character = (player :: any).Character
	if not character then
		warn(`[WeaponDistributor] {player.Name} has no character`)
		return
	end

	local backpack = player:FindFirstChildWhichIsA("Backpack")
	if not backpack then
		warn(`[WeaponDistributor] No Backpack found for {player.Name}`)
		return
	end

	local knifeTemplate = (knifeName and knifeTemplates[knifeName]) or defaultKnifeTemplate
	local gunTemplate = (gunName and gunTemplates[gunName]) or defaultGunTemplate

	--// Idempotency: skip if the tool is already in the backpack or equipped on the character.
	if not backpack:FindFirstChild(knifeTemplate.Name) and not character:FindFirstChild(knifeTemplate.Name) then
		local knife = knifeTemplate:Clone()
		knife:SetAttribute("IsKnife", true)
		knife.Parent = backpack
	end

	if not backpack:FindFirstChild(gunTemplate.Name) and not character:FindFirstChild(gunTemplate.Name) then
		local gun = gunTemplate:Clone()
		gun:SetAttribute("IsGun", true)
		gun.Parent = backpack
	end
end

--// Test-only: resets module state so tests can run in isolation
function WeaponDistributor._reset()
	knifeTemplates = {}
	defaultKnifeTemplate = nil
	gunTemplates = {}
	defaultGunTemplate = nil
end

return WeaponDistributor
