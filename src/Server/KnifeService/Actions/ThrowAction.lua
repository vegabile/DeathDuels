local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
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
ThrowAction.animationId = SharedConfigs.ThrowAnimationId

function ThrowAction.serverExecute(player: Player, playerState: any, directionVector: Vector3?)
	if not directionVector then
		warn(`[KNIFE] [ThrowAction] Throw requires directionVector from {player.Name}`)
		return
	end
	knifeTrace(`serverExecute start player={player.Name}`)

	local character = player.Character
	if not character then
		warn(`[KNIFE] [ThrowAction] No character for {player.Name}`)
		return
	end

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn(`[KNIFE] [ThrowAction] No knife tool found for throw: {player.Name}`)
		return
	end
	knifeTrace(`using knife tool {knifeTool.Name}`)
	playerState.lastDirection = directionVector
	knifeTrace(`stored lastDirection for {player.Name}`)

	local knifeFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if not knifeFolder then
		knifeFolder = Instance.new("Folder")
		knifeFolder.Name = "KnifeIgnoreFolder"
		knifeFolder.Parent = workspace
		knifeTrace("created KnifeIgnoreFolder before projectile spawn")
	else
		knifeTrace("found existing KnifeIgnoreFolder before projectile spawn")
	end

	local blacklist = {character, knifeFolder}
	local clientKnifeProjectiles = workspace:FindFirstChild("ClientKnifeProjectiles")
	if clientKnifeProjectiles then
		table.insert(blacklist, clientKnifeProjectiles)
	end
	knifeTrace("prepared blacklist for projectile")

	local handle = knifeTool:FindFirstChild("Handle")
	if handle then
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer ~= player then
				knifeTrace(`broadcasting throw to {otherPlayer.Name}`)
				NetworkRouter:Call("KnifeThrowBroadcast", otherPlayer, {
					throwerUserId = player.UserId,
					knifeName = knifeTool.Name,
					spawnCFrame = handle.CFrame,
					directionVector = directionVector,
				})
			else
				knifeTrace(`skip self broadcast for {player.Name}`)
			end
		end
	else
		warn(`[KNIFE] [ThrowAction] Handle missing on {knifeTool.Name} for {player.Name}`)
	end

	KnifeProjectileHandler.spawnProjectile(player, directionVector, knifeTool, blacklist, function(hitPlayer)
		knifeTrace(`callback hitPlayer={hitPlayer.Name}`)
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

		knifeTrace(`confirmed hit {player.Name} -> {hitPlayer.Name}`)

		local remoteName = `KnifeAction_{player.UserId}`
		NetworkRouter:Call(remoteName, player, {
			payloadType = "ProjectileHitConfirm",
			actionName = "Throw",
		})
		knifeTrace(`sent hit confirm to {player.Name}`)
	end)
end

function ThrowAction.serverCleanup(_player: Player, _playerState: any)
	--// Projectile cleanup is self-contained in KnifeProjectileHandler via Debris
end

return ThrowAction
