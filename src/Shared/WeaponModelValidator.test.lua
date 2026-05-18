local WeaponModelValidator = require(script.Parent.WeaponModelValidator)

local function makeTool(name)
	local tool = Instance.new("Tool")
	tool.Name = name
	return tool
end

local ok, reason = WeaponModelValidator.validateKnife(nil)
assert(ok == false and reason == "knife template must be a Tool instance", "knife validator rejects nil")

local notTool = Instance.new("Folder")
ok, reason = WeaponModelValidator.validateKnife(notTool)
assert(ok == false and reason == "knife template must be a Tool instance", "knife validator rejects non-tool")

local knife = makeTool("Knife")
ok, reason = WeaponModelValidator.validateKnife(knife)
assert(ok == false and reason == "knife template missing Handle", "knife requires Handle")

local badHandle = Instance.new("Folder")
badHandle.Name = "Handle"
badHandle.Parent = knife
ok, reason = WeaponModelValidator.validateKnife(knife)
assert(ok == false and reason == "knife Handle must be a BasePart", "knife Handle must be BasePart")
badHandle:Destroy()

local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Parent = knife
local badHitbox = Instance.new("Folder")
badHitbox.Name = "Hitbox"
badHitbox.Parent = knife
ok, reason = WeaponModelValidator.validateKnife(knife)
assert(ok == false and reason == "knife Hitbox must be a BasePart when present", "knife Hitbox must be BasePart")
badHitbox:Destroy()

ok, reason = WeaponModelValidator.validateKnife(knife)
assert(ok == true, tostring(reason))

local gun = makeTool("Gun")
local gunHandle = Instance.new("Part")
gunHandle.Name = "Handle"
gunHandle.Parent = gun
local badShootPoint = Instance.new("Folder")
badShootPoint.Name = "ShootPoint"
badShootPoint.Parent = gunHandle
ok, reason = WeaponModelValidator.validateGun(gun)
assert(ok == false and reason == "gun ShootPoint must be an Attachment when present", "gun ShootPoint must be Attachment")
badShootPoint:Destroy()

local shootAttachment = Instance.new("Attachment")
shootAttachment.Name = "ShootAttachment"
shootAttachment.Parent = gunHandle
ok, reason = WeaponModelValidator.validateGun(gun)
assert(ok == true, tostring(reason))

print("[WeaponModelValidator.test] passed")
return true
