local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponModelValidator = require(ReplicatedStorage.WeaponModelValidator)

local WeaponDistributor = {}

local knifeTemplates: { [string]: Tool } = {}
local knifeTemplatesLowercase: { [string]: Tool } = {}
local defaultKnifeTemplate: Tool? = nil
local gunTemplates: { [string]: Tool } = {}
local gunTemplatesLowercase: { [string]: Tool } = {}
local defaultGunTemplate: Tool? = nil

local function normalizeTemplateKey(name: string): string
	return string.lower(name)
end

local function resolveTemplate(
	requestedName: string?,
	templates: { [string]: Tool },
	lowercaseTemplates: { [string]: Tool },
	defaultTemplate: Tool
): Tool
	if type(requestedName) ~= "string" or requestedName == "" then
		return defaultTemplate
	end

	return templates[requestedName] or lowercaseTemplates[normalizeTemplateKey(requestedName)] or defaultTemplate
end

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
	local existing = tool:FindFirstChild("Hitbox")
	if existing then
		if not existing:IsA("BasePart") then
			error(`[WeaponDistributor] {tool.Name}.Hitbox must be a BasePart`)
		end
		return
	end

	local handle = tool:FindFirstChild("Handle") :: BasePart
	local bbCFrame, bbSize = tool:GetBoundingBox()

	
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

	
	hitbox.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = hitbox
	weld.Parent = hitbox
end

local function ensureGunShootPoint(tool: Tool)
	local handle = tool:FindFirstChild("Handle") :: BasePart

	local shootPoint = handle:FindFirstChild("ShootPoint")
	if shootPoint then
		if not shootPoint:IsA("Attachment") then
			error(`[WeaponDistributor] {tool.Name}.Handle.ShootPoint must be an Attachment`)
		end
		return
	end

	
	local existing = handle:FindFirstChild("ShootAttachment")
	if existing then
		if not existing:IsA("Attachment") then
			error(`[WeaponDistributor] {tool.Name}.Handle.ShootAttachment must be an Attachment`)
		end
		existing.Name = "ShootPoint"
		return
	end

	
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
		knifeTemplatesLowercase[normalizeTemplateKey(knife.Name)] = knife
		if i == 1 then defaultKnifeTemplate = knife end
	end
	for i, gun in guns do
		ensureGunShootPoint(gun)
		gunTemplates[gun.Name] = gun
		gunTemplatesLowercase[normalizeTemplateKey(gun.Name)] = gun
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

	local knifeTemplate = resolveTemplate(knifeName, knifeTemplates, knifeTemplatesLowercase, defaultKnifeTemplate)
	local gunTemplate = resolveTemplate(gunName, gunTemplates, gunTemplatesLowercase, defaultGunTemplate)

	
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


function WeaponDistributor._reset()
	knifeTemplates = {}
	knifeTemplatesLowercase = {}
	defaultKnifeTemplate = nil
	gunTemplates = {}
	gunTemplatesLowercase = {}
	defaultGunTemplate = nil
end

return WeaponDistributor
