local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)
local AnimationController = require(script.Parent.Parent.Parent.AnimationController)
local SFXController = require(script.Parent.Parent.Parent.SFXController)

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration
ThrowAction.animationId = SharedConfigs.ThrowAnimationId

local function getOrCreateClientFolder(): Folder
	local folderName = "ClientKnifeProjectiles"
	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		print("[KNIFE] [ClientThrowAction] creating ClientKnifeProjectiles folder")
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = workspace
	end
	return folder
end

function ThrowAction.clientExecute(_state, directionVector: Vector3?)
	print(`[KNIFE] [ClientThrowAction] clientExecute begin dirExists={directionVector ~= nil}`)
	if not directionVector then return end
	print("[KNIFE] [ClientThrowAction] directionVector accepted")

	local character = Players.LocalPlayer.Character
	if not character then
		warn("[KNIFE] [ClientThrowAction] clientExecute missing character")
		return
	end

	print("[KNIFE] [ClientThrowAction] playing throw animation/sfx")
	AnimationController.play(character, SharedConfigs.ThrowAnimationId)
	SFXController.playUI(SharedConfigs.ThrowSoundId)

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn("[KNIFE] [ClientThrowAction] No knife tool found for client cosmetic projectile")
		return
	end

	local handle = knifeTool:FindFirstChild("Handle")
	if not handle then
		warn("[KNIFE] [ClientThrowAction] Knife tool has no Handle")
		return
	end
	print(`[KNIFE] [ClientThrowAction] using handle {handle:GetFullName()}`)

	local clientFolder = getOrCreateClientFolder()
	print("[KNIFE] [ClientThrowAction] spawning cosmetic projectile")
	local blacklist = { character, clientFolder }
	local ignoreFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if ignoreFolder then
		print("[KNIFE] [ClientThrowAction] excluding workspace.KnifeIgnoreFolder from collision checks")
		table.insert(blacklist, ignoreFolder)
	end

	ProjectileFactory.spawnProjectile({
		template = knifeTool,
		directionVector = directionVector,
		spawnCFrame = handle.CFrame,
		parent = clientFolder,
		transparency = 0,
	}, Players.LocalPlayer, blacklist, nil)
end

return ThrowAction
