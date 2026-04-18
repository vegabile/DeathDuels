local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration

do
	local profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Throw)
	ThrowAction.animationId = (profile and profile.id) or ""
end

local function getOrCreateClientFolder(): Folder
	local folderName = "ClientKnifeProjectiles"
	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = workspace
	end
	return folder
end

--// clientExecute is invoked from the release callback in KnifeController, NOT at click time.
--// directionVector is the rest-origin-computed direction; spawnCFrame is the animated visual CFrame.
function ThrowAction.clientExecute(_state, directionVector: Vector3?, spawnCFrame: CFrame?)
	if not directionVector or not spawnCFrame then return end

	local character = Players.LocalPlayer.Character
	if not character then
		warn("[KNIFE] [ClientThrowAction] no character")
		return
	end

	SFXController.playUI(SharedConfigs.ThrowSoundId)

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn("[KNIFE] [ClientThrowAction] no knife tool")
		return
	end

	local clientFolder = getOrCreateClientFolder()
	local blacklist = { character, clientFolder }
	local ignoreFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if ignoreFolder then
		table.insert(blacklist, ignoreFolder)
	end

	ProjectileFactory.spawnProjectile({
		template = knifeTool,
		directionVector = directionVector,
		spawnCFrame = spawnCFrame,
		parent = clientFolder,
		transparency = 0,
	}, Players.LocalPlayer, blacklist, nil)
end

return ThrowAction
