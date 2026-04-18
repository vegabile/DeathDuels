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
	print("[KNIFE] " .. message)
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

	--// Distance-bound the restOrigin against HRP.
	if (restOrigin - hrp.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance then
		warn(`[KNIFE] [ThrowAction] restOrigin out of range for {player.Name}`)
		return
	end

	--// Validate spawnCFrame or fall back.
	local effectiveSpawnCFrame = spawnCFrame
	if effectiveSpawnCFrame ~= nil
		and (typeof(effectiveSpawnCFrame) ~= "CFrame"
			or (effectiveSpawnCFrame.Position - hrp.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance)
	then
		warn(`[KNIFE] [ThrowAction] spawnCFrame invalid — falling back to restOrigin`)
		effectiveSpawnCFrame = CFrame.new(restOrigin)
	elseif effectiveSpawnCFrame == nil then
		effectiveSpawnCFrame = CFrame.new(restOrigin)
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

	--// Broadcast to other players with effectiveSpawnCFrame for visual consistency.
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			NetworkRouter:Call("KnifeThrowBroadcast", otherPlayer, {
				throwerUserId = player.UserId,
				knifeName = knifeTool.Name,
				spawnCFrame = effectiveSpawnCFrame,
				directionVector = directionVector,
			})
		end
	end

	--// Authoritative projectile uses restOrigin as its spawn — gameplay is rest-pose-deterministic.
	local authoritativeSpawn = CFrame.new(restOrigin)

	KnifeProjectileHandler.spawnProjectile(
		player,
		directionVector,
		knifeTool,
		blacklist,
		function(hitPlayer)
			if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then return end
			local humanoid = hitPlayer.Character and hitPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:SetAttribute("LastDamageSource", player.UserId)
				humanoid:TakeDamage(SharedConfigs.ThrowDamage)
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
	--// Projectile cleanup is self-contained in KnifeProjectileHandler via Debris
end

return ThrowAction
