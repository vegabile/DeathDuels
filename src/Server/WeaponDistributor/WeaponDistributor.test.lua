local WeaponDistributor = require(script.Parent)

WeaponDistributor._reset()

local function makeTool(name, attachmentName)
	local tool = Instance.new("Tool")
	tool.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2, 2, 2)
	handle.Parent = tool
	if attachmentName then
		local attachment = Instance.new("Attachment")
		attachment.Name = attachmentName
		attachment.Parent = handle
	end
	return tool
end

local knife = makeTool("DefaultKnife")
local gun = makeTool("DefaultGun", "ShootAttachment")

assert(WeaponDistributor.init({}, { gun }) == false, "init rejects missing knives")
assert(WeaponDistributor.init({ knife }, {}) == false, "init rejects missing guns")
assert(WeaponDistributor.init({ knife }, { gun }) == true, "init accepts valid templates")

local knifeHandle = knife:FindFirstChild("Handle")
assert(knifeHandle.Massless == true and knifeHandle.CanCollide == false and knifeHandle.Anchored == false, "knife handle is normalized")
assert(knife:FindFirstChild("Hitbox") ~= nil, "knife hitbox is created when missing")
assert(gun:FindFirstChild("Handle"):FindFirstChild("ShootPoint") ~= nil, "gun ShootAttachment is normalized to ShootPoint")

local player = Instance.new("Player")
player.Name = "Armed"
player.UserId = 808
local character = Instance.new("Model")
character.Name = "Character"
player.Character = character
local backpack = Instance.new("Backpack")
backpack.Name = "Backpack"
backpack.Parent = player

WeaponDistributor.distributeToPlayer(player, "defaultknife", "defaultgun")
local distributedKnife = backpack:FindFirstChild("DefaultKnife")
local distributedGun = backpack:FindFirstChild("DefaultGun")
assert(distributedKnife ~= nil and distributedKnife:GetAttribute("IsKnife") == true, "knife clone is distributed and marked")
assert(distributedGun ~= nil and distributedGun:GetAttribute("IsGun") == true, "gun clone is distributed and marked")

WeaponDistributor.distributeToPlayer(player, "DefaultKnife", "DefaultGun")
assert(#backpack:GetChildren() == 2, "distribution does not duplicate existing weapons")

WeaponDistributor.distributeToPlayer(player, 123, false)
assert(#backpack:GetChildren() == 2, "non-string requested weapon names fall back without error or duplicates")

WeaponDistributor._reset()

print("[WeaponDistributor.test] passed")
return true
