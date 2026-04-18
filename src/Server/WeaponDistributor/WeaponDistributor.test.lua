--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeaponModelValidator = require(ReplicatedStorage.WeaponModelValidator)
local WeaponDistributor = require(ServerScriptService.WeaponDistributor)

local passed = 0
local failed = 0

local function check(label: string, condition: boolean, detail: string?)
	if condition then
		print(`PASS: {label}`)
		passed += 1
	else
		print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
		failed += 1
	end
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local cleanup = {}

local function track(inst: Instance)
	table.insert(cleanup, inst)
	return inst
end

local function makeTool(name: string): Tool
	local t = Instance.new("Tool")
	t.Name = name
	t.Parent = workspace
	return track(t)
end

local function addHandle(tool: Tool, isMesh: boolean?): BasePart
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 3.0, 0.7)
	handle.Parent = tool
	return handle
end

local function addHitbox(tool: Tool): Part
	local h = Instance.new("Part")
	h.Name = "Hitbox"
	h.CanCollide = false
	h.Parent = tool
	return h
end

local function addAttachment(handle: BasePart, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = handle
	return a
end

local function makePlayerWithBackpack(): (Instance, Instance)
	local player = Instance.new("Folder")
	player.Name = "MockPlayer"
	local backpack = Instance.new("Backpack")
	backpack.Parent = player
	local character = Instance.new("Model")
	character.Name = "Character"
	character.Parent = player
	player.Parent = workspace
	track(player)
	return player, backpack
end

local function makePlayerNoBackpack(): Instance
	local player = Instance.new("Folder")
	player.Name = "MockPlayerNoBackpack"
	local character = Instance.new("Model")
	character.Name = "Character"
	character.Parent = player
	player.Parent = workspace
	track(player)
	return player
end

local function cleanAll()
	for _, inst in cleanup do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(cleanup)
	WeaponDistributor._reset()
end

-- ─── WeaponModelValidator: validateKnife ─────────────────────────────────────

do
	local ok, err = WeaponModelValidator.validateKnife(nil)
	check("validateKnife nil → false", not ok)
	check("validateKnife nil → error string", type(err) == "string")

	local ok2, err2 = WeaponModelValidator.validateKnife(123)
	check("validateKnife number → false", not ok2)

	local part = track(Instance.new("Part"))
	part.Parent = workspace
	local ok3, err3 = WeaponModelValidator.validateKnife(part)
	check("validateKnife Part → false", not ok3)
	check("validateKnife Part → error mentions Tool", err3 ~= nil and err3:find("Tool") ~= nil)

	local toolNoHandle = makeTool("KnifeNoHandle")
	local ok4, err4 = WeaponModelValidator.validateKnife(toolNoHandle)
	check("validateKnife Tool no Handle → false", not ok4)
	check("validateKnife Tool no Handle → error mentions Handle", err4 ~= nil and err4:find("Handle") ~= nil)

	--// Handle is a Script, not a BasePart
	local toolBadHandle = makeTool("KnifeBadHandle")
	local badHandle = Instance.new("Script")
	badHandle.Name = "Handle"
	badHandle.Parent = toolBadHandle
	local ok5, err5 = WeaponModelValidator.validateKnife(toolBadHandle)
	check("validateKnife non-BasePart Handle → false", not ok5)
	check("validateKnife non-BasePart Handle → error mentions BasePart", err5 ~= nil and err5:find("BasePart") ~= nil)

	local toolOk = makeTool("KnifeOk")
	addHandle(toolOk)
	local ok6, err6 = WeaponModelValidator.validateKnife(toolOk)
	check("validateKnife valid Tool → true", ok6, err6)
	check("validateKnife valid Tool → no error", err6 == nil)

	cleanAll()
end

-- ─── WeaponModelValidator: validateGun ───────────────────────────────────────

do
	local ok, _ = WeaponModelValidator.validateGun(nil)
	check("validateGun nil → false", not ok)

	local toolNoHandle = makeTool("GunNoHandle")
	local ok2, err2 = WeaponModelValidator.validateGun(toolNoHandle)
	check("validateGun Tool no Handle → false", not ok2)
	check("validateGun Tool no Handle → error mentions Handle", err2 ~= nil and err2:find("Handle") ~= nil)

	local toolOk = makeTool("GunOk")
	local h = addHandle(toolOk)
	h.Size = Vector3.new(0.2, 1.0, 1.5)
	local ok3, err3 = WeaponModelValidator.validateGun(toolOk)
	check("validateGun valid Tool → true", ok3, err3)
	check("validateGun valid Tool → no error", err3 == nil)

	cleanAll()
end

-- ─── WeaponDistributor.init: validation failures ─────────────────────────────

do
	WeaponDistributor._reset()

	local badKnife = track(Instance.new("Part"))
	badKnife.Parent = workspace
	local validGun = makeTool("GunForInitTest")
	addHandle(validGun)

	local ok = WeaponDistributor.init({badKnife}, {validGun})
	check("init invalid knife → false", not ok)

	local validKnife = makeTool("KnifeForInitTest")
	addHandle(validKnife)
	local badGun = track(Instance.new("Part"))
	badGun.Parent = workspace

	local ok2 = WeaponDistributor.init({validKnife}, {badGun})
	check("init invalid gun → false", not ok2)

	cleanAll()
end

-- ─── ensureKnifeHitbox ────────────────────────────────────────────────────────

do
	WeaponDistributor._reset()

	--// No Hitbox present — should be created
	local knifeNoHitbox = makeTool("KnifeNoHitbox")
	addHandle(knifeNoHitbox)
	local gun = makeTool("GunForHitboxTest")
	local gunHandle = addHandle(gun)
	addAttachment(gunHandle, "ShootPoint")

	local ok = WeaponDistributor.init({knifeNoHitbox}, {gun})
	check("init knife without Hitbox → true", ok)

	local hitbox = knifeNoHitbox:FindFirstChild("Hitbox")
	check("Hitbox created on knife", hitbox ~= nil)
	check("Hitbox is a Part", hitbox ~= nil and hitbox:IsA("Part"))
	check("Hitbox CanCollide = false", hitbox ~= nil and hitbox.CanCollide == false)
	check("Hitbox Transparency = 1", hitbox ~= nil and hitbox.Transparency == 1)
	check("Hitbox has WeldConstraint", hitbox ~= nil and hitbox:FindFirstChildWhichIsA("WeldConstraint") ~= nil)

	local weld = hitbox and hitbox:FindFirstChildWhichIsA("WeldConstraint")
	local knifeHandle = knifeNoHitbox:FindFirstChild("Handle")
	check("WeldConstraint.Part0 = Handle", weld ~= nil and weld.Part0 == knifeHandle)
	check("WeldConstraint.Part1 = Hitbox", weld ~= nil and weld.Part1 == hitbox)

	cleanAll()
end

do
	WeaponDistributor._reset()

	--// Hitbox already present — no duplicate should be added
	local knifeWithHitbox = makeTool("KnifeWithHitbox")
	addHandle(knifeWithHitbox)
	addHitbox(knifeWithHitbox)
	local gun2 = makeTool("GunForHitboxTest2")
	local gunHandle2 = addHandle(gun2)
	addAttachment(gunHandle2, "ShootPoint")

	WeaponDistributor.init({knifeWithHitbox}, {gun2})
	local hitboxCount = 0
	for _, child in knifeWithHitbox:GetChildren() do
		if child.Name == "Hitbox" then hitboxCount += 1 end
	end
	check("Existing Hitbox not duplicated", hitboxCount == 1)

	cleanAll()
end

-- ─── ensureGunShootPoint ──────────────────────────────────────────────────────

do
	WeaponDistributor._reset()

	--// ShootAttachment present — should be renamed to ShootPoint
	local knife = makeTool("KnifeForGunTest")
	addHandle(knife)
	local gunWithAttach = makeTool("GunWithShootAttachment")
	local gHandle = addHandle(gunWithAttach)
	gHandle.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gHandle, "ShootAttachment")

	WeaponDistributor.init({knife}, {gunWithAttach})
	check("ShootAttachment renamed to ShootPoint", gHandle:FindFirstChild("ShootPoint") ~= nil)
	check("ShootAttachment no longer exists after rename", gHandle:FindFirstChild("ShootAttachment") == nil)

	cleanAll()
end

do
	WeaponDistributor._reset()

	--// No attachment at all — ShootPoint should be created
	local knife2 = makeTool("KnifeForGunTest2")
	addHandle(knife2)
	local gunNoAttach = makeTool("GunNoAttachment")
	local gHandle2 = addHandle(gunNoAttach)
	gHandle2.Size = Vector3.new(0.2, 1.0, 1.5)

	WeaponDistributor.init({knife2}, {gunNoAttach})
	local sp = gHandle2:FindFirstChild("ShootPoint")
	check("ShootPoint created when absent", sp ~= nil)
	check("ShootPoint is Attachment", sp ~= nil and sp:IsA("Attachment"))

	cleanAll()
end

do
	WeaponDistributor._reset()

	--// ShootPoint already present — must not be duplicated or overwritten
	local knife3 = makeTool("KnifeForGunTest3")
	addHandle(knife3)
	local gunWithShootPoint = makeTool("GunWithShootPoint")
	local gHandle3 = addHandle(gunWithShootPoint)
	local original = addAttachment(gHandle3, "ShootPoint")
	original.Position = Vector3.new(1, 2, 3)

	WeaponDistributor.init({knife3}, {gunWithShootPoint})
	local sp3 = gHandle3:FindFirstChild("ShootPoint")
	check("ShootPoint unchanged when already present", sp3 == original)
	check("ShootPoint position preserved", sp3 ~= nil and sp3.Position == Vector3.new(1, 2, 3))

	cleanAll()
end

-- ─── WeaponDistributor.distributeToPlayer ─────────────────────────────────────

do
	WeaponDistributor._reset()

	--// Not initialized — should warn but not throw
	local mockPlayer, _ = makePlayerWithBackpack()
	local ok = pcall(WeaponDistributor.distributeToPlayer, mockPlayer)
	check("distributeToPlayer when not init → no throw", ok)

	cleanAll()
end

do
	--// Player has no Backpack — should warn but not throw
	WeaponDistributor._reset()
	local knife = makeTool("KnifeForDistTest")
	addHandle(knife)
	local gun = makeTool("GunForDistTest")
	local gh = addHandle(gun)
	addAttachment(gh, "ShootPoint")
	WeaponDistributor.init({knife}, {gun})

	local noBackpackPlayer = makePlayerNoBackpack()
	local ok = pcall(WeaponDistributor.distributeToPlayer, noBackpackPlayer)
	check("distributeToPlayer no Backpack → no throw", ok)

	cleanAll()
end

do
	--// Happy path: both tools land in Backpack with correct attributes
	WeaponDistributor._reset()
	local knife = makeTool("KnifeForDistTest2")
	addHandle(knife)
	local gun = makeTool("GunForDistTest2")
	local gh = addHandle(gun)
	addAttachment(gh, "ShootPoint")
	WeaponDistributor.init({knife}, {gun})

	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer)

	local knifeInBackpack = backpack:FindFirstChildWhichIsA("Tool", true)
	local tools: { Tool } = {}
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") then
			table.insert(tools, child)
		end
	end

	check("Two tools in Backpack after distribute", #tools == 2)

	local hasKnife = false
	local hasGun = false
	for _, tool in tools do
		if tool:GetAttribute("IsKnife") == true then hasKnife = true end
		if tool:GetAttribute("IsGun") == true then hasGun = true end
	end
	check("Distributed knife has IsKnife attribute", hasKnife)
	check("Distributed gun has IsGun attribute", hasGun)

	--// Templates themselves must NOT have IsKnife/IsGun set (only clones do)
	check("Knife template does not have IsKnife (set on clone only)", knife:GetAttribute("IsKnife") == nil)
	check("Gun template does not have IsGun (set on clone only)", gun:GetAttribute("IsGun") == nil)

	--// Distributed knife clone must have Hitbox
	local distributedKnife = nil
	for _, tool in tools do
		if tool:GetAttribute("IsKnife") then distributedKnife = tool break end
	end
	check("Distributed knife clone has Hitbox", distributedKnife ~= nil and distributedKnife:FindFirstChild("Hitbox") ~= nil)

	cleanAll()
end

-- ─── distributeToPlayer idempotency ───────────────────────────────────────────

do
	WeaponDistributor._reset()
	local k1 = makeTool("IdemKnife")
	addHandle(k1)
	local g1 = makeTool("IdemGun")
	local gh = addHandle(g1)
	gh.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gh, "ShootPoint")
	local initOk = WeaponDistributor.init({ k1 }, { g1 })
	check("idempotent: init ok", initOk)

	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, "IdemKnife", "IdemGun")
	WeaponDistributor.distributeToPlayer(mockPlayer, "IdemKnife", "IdemGun")

	local knifeCount = 0
	local gunCount = 0
	for _, child in backpack:GetChildren() do
		if child.Name == "IdemKnife" then knifeCount += 1 end
		if child.Name == "IdemGun" then gunCount += 1 end
	end
	check("idempotent: exactly one knife after two calls", knifeCount == 1)
	check("idempotent: exactly one gun after two calls", gunCount == 1)

	cleanAll()
end

-- ─── Multi-knife selection ────────────────────────────────────────────────────

do
	WeaponDistributor._reset()

	local knifeA = makeTool("KnifeAlpha")
	addHandle(knifeA)
	local knifeB = makeTool("KnifeBeta")
	addHandle(knifeB)

	local gun = makeTool("GunForMultiKnifeTest")
	local gh = addHandle(gun)
	addAttachment(gh, "ShootPoint")

	local ok = WeaponDistributor.init({knifeA, knifeB}, {gun})
	check("init with two knives → true", ok)

	--// Distribute with specific knife name
	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, "KnifeBeta")

	local distributedKnife = nil
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			distributedKnife = child
			break
		end
	end
	check("Named knife distributed", distributedKnife ~= nil)
	check("Distributed knife is KnifeBeta", distributedKnife ~= nil and distributedKnife.Name == "KnifeBeta")

	cleanAll()
end

do
	WeaponDistributor._reset()

	local knifeA = makeTool("KnifeAlphaCase")
	addHandle(knifeA)
	local knifeB = makeTool("KnifeBetaCase")
	addHandle(knifeB)

	local gun = makeTool("GunForCaseInsensitiveKnifeTest")
	local gh = addHandle(gun)
	addAttachment(gh, "ShootPoint")

	local ok = WeaponDistributor.init({knifeA, knifeB}, {gun})
	check("init with two knives for case-insensitive lookup → true", ok)

	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, "knIFebEtaCaSe")

	local distributedKnife = nil
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			distributedKnife = child
			break
		end
	end
	check("Case-insensitive knife distributed", distributedKnife ~= nil)
	check("Case-insensitive knife is KnifeBetaCase", distributedKnife ~= nil and distributedKnife.Name == "KnifeBetaCase")

	cleanAll()
end

do
	WeaponDistributor._reset()

	local knifeA = makeTool("KnifeAlpha2")
	addHandle(knifeA)
	local knifeB = makeTool("KnifeBeta2")
	addHandle(knifeB)

	local gun = makeTool("GunForFallbackTest")
	local gh = addHandle(gun)
	addAttachment(gh, "ShootPoint")

	WeaponDistributor.init({knifeA, knifeB}, {gun})

	--// Distribute with unknown name → falls back to default (first)
	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, "NonExistentKnife")

	local distributedKnife = nil
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			distributedKnife = child
			break
		end
	end
	check("Fallback knife distributed for unknown name", distributedKnife ~= nil)
	check("Fallback knife is first template (KnifeAlpha2)", distributedKnife ~= nil and distributedKnife.Name == "KnifeAlpha2")

	cleanAll()
end

-- ─── Gun selection by name ────────────────────────────────────────────────────

do
	WeaponDistributor._reset()

	local knife = makeTool("KnifeForGunSelect")
	addHandle(knife)

	local gunA = makeTool("GunAlpha")
	local gunAHandle = addHandle(gunA)
	gunAHandle.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gunAHandle, "ShootPoint")

	local gunB = makeTool("GunBeta")
	local gunBHandle = addHandle(gunB)
	gunBHandle.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gunBHandle, "ShootPoint")

	local ok = WeaponDistributor.init({knife}, {gunA, gunB})
	check("init multi-gun → true", ok)

	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, nil, "GunBeta")

	local delivered
	for _, child in backpack:GetChildren() do
		if child:GetAttribute("IsGun") then delivered = child end
	end
	check("distributeToPlayer picks gun by name", delivered ~= nil and delivered.Name == "GunBeta")

	cleanAll()
end

do
	WeaponDistributor._reset()

	local knife = makeTool("KnifeForGunCaseSelect")
	addHandle(knife)

	local gunA = makeTool("GunAlphaCase")
	local gunAHandle = addHandle(gunA)
	gunAHandle.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gunAHandle, "ShootPoint")

	local gunB = makeTool("GunBetaCase")
	local gunBHandle = addHandle(gunB)
	gunBHandle.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gunBHandle, "ShootPoint")

	local ok = WeaponDistributor.init({knife}, {gunA, gunB})
	check("init multi-gun for case-insensitive lookup → true", ok)

	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, nil, "gUNbeTAcASe")

	local delivered
	for _, child in backpack:GetChildren() do
		if child:GetAttribute("IsGun") then delivered = child end
	end
	check("distributeToPlayer picks gun by name case-insensitively", delivered ~= nil and delivered.Name == "GunBetaCase")

	cleanAll()
end

do
	WeaponDistributor._reset()

	local knife = makeTool("KnifeForGunFallback")
	addHandle(knife)

	local gunA = makeTool("GunAlpha2")
	local gunAHandle = addHandle(gunA)
	gunAHandle.Size = Vector3.new(0.2, 1.0, 1.5)
	addAttachment(gunAHandle, "ShootPoint")

	WeaponDistributor.init({knife}, {gunA})

	local mockPlayer, backpack = makePlayerWithBackpack()
	WeaponDistributor.distributeToPlayer(mockPlayer, nil, "NonExistentGun")

	local delivered
	for _, child in backpack:GetChildren() do
		if child:GetAttribute("IsGun") then delivered = child end
	end
	check("unknown gunName → falls back to default", delivered ~= nil and delivered.Name == "GunAlpha2")

	cleanAll()
end

-- ─── Summary ──────────────────────────────────────────────────────────────────

print(`\n{passed} passed, {failed} failed`)
