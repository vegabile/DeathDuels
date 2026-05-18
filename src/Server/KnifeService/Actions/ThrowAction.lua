local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local AnimationsConfigs = require(ReplicatedStorage.Animations.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)

local KnifeProjectileHandler = require(script.Parent.Parent.KnifeProjectileHandler)
local TeleportMetadataService = require(script.Parent.Parent.Parent.RoundService.TeleportMetadataService)

local function knifeTrace(message: string)
	if SharedConfigs.DEBUG_MODE then
		print(`[ThrowAction] {message}`)
	end
end

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration
do
	local _profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Throw)
	ThrowAction.animationId = (_profile and _profile.id) or ""
end

function ThrowAction.serverExecute(
	player: Player,
	playerState: any,
	directionVector: Vector3?,
	restOrigin: Vector3?,
	spawnCFrame: CFrame?
)
	if not directionVector then
		warn(`[KNIFE] [ThrowAction] missing directionVector for {player.Name}`)
		return
	end
	if not restOrigin then
		warn(`[KNIFE] [ThrowAction] missing restOrigin for {player.Name}`)
		return
	end

	local character = player.Character
	if not character then
		warn(`[KNIFE] [ThrowAction] no character for {player.Name}`)
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn(`[KNIFE] [ThrowAction] no HumanoidRootPart for {player.Name}`)
		return
	end

	
	if (restOrigin - hrp.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance then
		warn(`[KNIFE] [ThrowAction] restOrigin out of range for {player.Name}`)
		return
	end

	
	
	if spawnCFrame ~= nil
		and (typeof(spawnCFrame) ~= "CFrame"
			or (spawnCFrame.Position - hrp.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance)
	then
		warn(`[KNIFE] [ThrowAction] spawnCFrame invalid - ignoring cosmetic pose`)
	end

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn(`[KNIFE] [ThrowAction] no knife tool for {player.Name}`)
		return
	end
	playerState.lastDirection = directionVector

	local knifeFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if not knifeFolder then
		knifeFolder = Instance.new("Folder")
		knifeFolder.Name = "KnifeIgnoreFolder"
		knifeFolder.Parent = workspace
	end

	local blacklist = { character, knifeFolder }
	local clientKnifeProjectiles = workspace:FindFirstChild("ClientKnifeProjectiles")
	if clientKnifeProjectiles then
		table.insert(blacklist, clientKnifeProjectiles)
	end

	
	
	local authoritativeSpawn = CFrame.new(restOrigin)
	local broadcastSpawn = authoritativeSpawn
	if typeof(spawnCFrame) == "CFrame"
		and (spawnCFrame.Position - hrp.Position).Magnitude <= AnimationsConfigs.MaxRestOriginDistance
	then
		broadcastSpawn = spawnCFrame
	end

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			NetworkRouter:Call("KnifeThrowBroadcast", otherPlayer, {
				throwerUserId = player.UserId,
				knifeName = knifeTool.Name,
				directionVector = directionVector,
				spawnCFrame = broadcastSpawn,
			})
		end
	end

	KnifeProjectileHandler.spawnProjectile(
		player,
		directionVector,
		knifeTool,
		blacklist,
		function(hitPlayer)
			if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then return end

			if hitPlayer:GetAttribute("ShieldActive") then
				hitPlayer:SetAttribute("ShieldActive", nil)
				knifeTrace(`ShieldActive absorbed throw on {hitPlayer.Name}`)
				return
			end

			local humanoid = hitPlayer.Character and hitPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:SetAttribute("LastDamageSource", player.UserId)
				humanoid:TakeDamage(SharedConfigs.ThrowDamage)
				knifeTrace(`damaged {hitPlayer.Name} for {SharedConfigs.ThrowDamage}`)
			end

			NetworkRouter:Call(`KnifeAction_{player.UserId}`, player, {
				payloadType = "ProjectileHitConfirm",
				actionName = "Throw",
			})
		end,
		authoritativeSpawn
	)
end

function ThrowAction.serverCleanup(_player: Player, _playerState: any)
	
end

return ThrowAction
