local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)

local ServerConfigs = require(script.Parent.Parent.Configs)
local KnifeProjectileHandler = require(script.Parent.Parent.KnifeProjectileHandler)

local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local ThrowAction = {}

ThrowAction.name = "Throw"
ThrowAction.cooldown = SharedConfigs.ThrowCooldown
ThrowAction.duration = SharedConfigs.ThrowDuration
ThrowAction.animationId = SharedConfigs.ThrowAnimationId

function ThrowAction.serverExecute(player: Player, playerState: any, directionVector: Vector3?)
	if not directionVector then
		warn(`[ThrowAction] Throw requires directionVector from {player.Name}`)
		return
	end

	local character = player.Character
	if not character then
		warn(`[ThrowAction] No character for {player.Name}`)
		return
	end

	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn(`[ThrowAction] No knife tool found for throw: {player.Name}`)
		return
	end

	local knifeFolder = workspace:FindFirstChild("KnifeIgnoreFolder") or workspace
	local blacklist = {character, knifeFolder}

	--// The knife tool itself is the projectile template
	KnifeProjectileHandler.spawnProjectile(player, directionVector, knifeTool, blacklist, function(hitPlayer)
		local humanoid = hitPlayer.Character and hitPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(SharedConfigs.ThrowDamage)
		end

		debugPrint(DEBUG, `[ThrowAction] {player.Name}'s thrown knife hit {hitPlayer.Name}`)

		local remoteName = `KnifeAction_{player.UserId}`
		NetworkRouter:Call(remoteName, player, {
			payloadType = "ProjectileHitConfirm",
			actionName = "Throw",
		})
	end)
end

function ThrowAction.serverCleanup(_player: Player, _playerState: any)
	--// Projectile cleanup is self-contained in KnifeProjectileHandler via Debris
end

return ThrowAction
