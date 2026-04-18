--// Run via mcp__robloxstudio__execute_luau in the edit environment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)

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

local profiles = {
	SmallPistol = {
		[AnimationType.Idle]  = { id = "rbxassetid://111" },
		[AnimationType.Shoot] = { id = "rbxassetid://222", releaseTime = 0.1 },
	},
	Knife = {
		[AnimationType.Throw] = { id = "rbxassetid://333", releaseTime = 0.2 },
		[AnimationType.Stab]  = { id = "" },
	},
}

do
	local entry = AnimationProfile.resolve("SmallPistol", profiles, AnimationType.Idle)
	check("resolves known tool + type", entry ~= nil and entry.id == "rbxassetid://111")
end

do
	local entry = AnimationProfile.resolve("SmallPistol", profiles, AnimationType.Shoot)
	check("returns releaseTime when set", entry ~= nil and entry.releaseTime == 0.1)
end

do
	local entry = AnimationProfile.resolve("Knife", profiles, AnimationType.Stab)
	check("returns entry with blank id", entry ~= nil and entry.id == "")
	check("blank id entry has no releaseTime", entry ~= nil and entry.releaseTime == nil)
end

do
	local entry = AnimationProfile.resolve("UnknownTool", profiles, AnimationType.Idle)
	check("unknown tool returns nil", entry == nil)
end

do
	local entry = AnimationProfile.resolve("SmallPistol", profiles, "BogusType")
	check("unknown type returns nil", entry == nil)
end

do
	local entry = AnimationProfile.resolve("SmallPistol", nil :: any, AnimationType.Idle)
	check("nil profiles table returns nil", entry == nil)
end

print(`\n--- {passed} passed, {failed} failed ---`)
