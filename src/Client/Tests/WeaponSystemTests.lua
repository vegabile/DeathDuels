local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterPlayerScripts = game:GetService("StarterPlayer").StarterPlayerScripts

local WeaponSystemTests = {}

local failCount = 0
local passCount = 0

local function check(condition: boolean, label: string)
	if not condition then
		warn("[FAIL] " .. label)
		failCount += 1
	else
		print("[PASS] " .. label)
		passCount += 1
	end
end

local function runT1_ConfigValues()
	local GunConfigs = require(ReplicatedStorage.Gun.Configs)
	local KnifeConfigs = require(ReplicatedStorage.Knife.Configs)

	check(GunConfigs.ShootDamage == 100, "GunConfigs.ShootDamage == 100")
	check(GunConfigs.ShootCooldown == 5, "GunConfigs.ShootCooldown == 5")
	check(type(GunConfigs.ShootSoundId) == "string", "GunConfigs.ShootSoundId is string")
	check(type(GunConfigs.HitSoundId) == "string", "GunConfigs.HitSoundId is string")

	check(KnifeConfigs.StabDamage == 100, "KnifeConfigs.StabDamage == 100")
	check(KnifeConfigs.ThrowDamage == 100, "KnifeConfigs.ThrowDamage == 100")
	check(KnifeConfigs.StabCooldown == 5, "KnifeConfigs.StabCooldown == 5")
	check(KnifeConfigs.ThrowCooldown == 5, "KnifeConfigs.ThrowCooldown == 5")
	check(type(KnifeConfigs.StabSoundId) == "string", "KnifeConfigs.StabSoundId is string")
	check(type(KnifeConfigs.ThrowSoundId) == "string", "KnifeConfigs.ThrowSoundId is string")
	check(type(KnifeConfigs.HitSoundId) == "string", "KnifeConfigs.HitSoundId is string")
	check(type(KnifeConfigs.StickSoundId) == "string", "KnifeConfigs.StickSoundId is string")
end

local function runT2_AnimationController_BlankId()
	local AnimationController = require(StarterPlayerScripts.AnimationController)

	local mockChar = Instance.new("Model")
	local hum = Instance.new("Humanoid", mockChar)
	Instance.new("Animator", hum)
	mockChar.Parent = workspace

	local handle = AnimationController.play(mockChar, "")
	check(type(handle) == "table", "AnimationController.play blank ID returns table handle")
	check(type(handle.stop) == "function", "AnimationController.play blank ID handle.stop is function")

	local ok = pcall(handle.stop)
	check(ok, "AnimationController blank ID handle.stop does not error")

	mockChar:Destroy()
end

local function runT3_AnimationController_NoAnimator()
	local AnimationController = require(StarterPlayerScripts.AnimationController)

	local mockChar = Instance.new("Model")
	mockChar.Parent = workspace

	local handle = AnimationController.play(mockChar, "rbxassetid://123456")
	check(type(handle) == "table", "AnimationController.play no Animator returns table handle")
	check(type(handle.stop) == "function", "AnimationController.play no Animator handle.stop is function")

	local ok = pcall(handle.stop)
	check(ok, "AnimationController no Animator handle.stop does not error")

	mockChar:Destroy()
end

local function runT4_SFXController_BlankId()
	local SFXController = require(StarterPlayerScripts.SFXController)

	local ok1 = pcall(SFXController.playUI, "")
	check(ok1, "SFXController.playUI blank ID does not error")

	local ok2 = pcall(SFXController.playAt, "", Vector3.new(0, 0, 0))
	check(ok2, "SFXController.playAt blank ID does not error")
end

local function runT5_SFXController_PlayUI_CreatesSound()
	local SFXController = require(StarterPlayerScripts.SFXController)

	local countBefore = #SoundService:GetChildren()
	SFXController.playUI("rbxassetid://9119835571")
	local countAfter = #SoundService:GetChildren()

	check(countAfter > countBefore, "SFXController.playUI creates a Sound in SoundService")
end

local function runT6_SFXController_PlayAt_CreatesPart()
	local SFXController = require(StarterPlayerScripts.SFXController)

	local testPos = Vector3.new(999, 500, 999)
	SFXController.playAt("rbxassetid://9119835571", testPos)

	local found = false
	for _, obj in workspace:GetChildren() do
		if obj:IsA("Part") and obj:FindFirstChildWhichIsA("Sound") then
			if (obj.Position - testPos).Magnitude < 0.1 then
				found = true
				break
			end
		end
	end
	check(found, "SFXController.playAt creates anchored Part with Sound at position")
end

function WeaponSystemTests.run()
	failCount = 0
	passCount = 0

	print("--- WeaponSystemTests START ---")

	runT1_ConfigValues()
	runT2_AnimationController_BlankId()
	runT3_AnimationController_NoAnimator()
	runT4_SFXController_BlankId()
	runT5_SFXController_PlayUI_CreatesSound()
	runT6_SFXController_PlayAt_CreatesPart()

	print("--- WeaponSystemTests END ---")
	if failCount == 0 then
		print(`ALL TESTS PASSED ({passCount}/{passCount})`)
	else
		warn(`{failCount} TEST(S) FAILED ({passCount}/{passCount + failCount} passed)`)
	end
end

return WeaponSystemTests
