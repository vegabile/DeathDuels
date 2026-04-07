local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local GunUtility = require(ReplicatedStorage.Gun.GunUtility)

local ServerConfigs = require(script.Parent.Parent.Configs)
local TeleportMetadataService = require(script.Parent.Parent.Parent.RoundService.TeleportMetadataService)
local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration
ShootAction.animationId = SharedConfigs.ShootAnimationId

local function drawTracer(origin: Vector3, hitPos: Vector3)
	local distance = (hitPos - origin).Magnitude
	if distance < 0.1 then return end

	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.new(1, 1, 0)
	tracer.Size = Vector3.new(SharedConfigs.TracerWidth, SharedConfigs.TracerWidth, distance)
	tracer.CFrame = CFrame.lookAt(origin, hitPos) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace

	Debris:AddItem(tracer, SharedConfigs.TracerDuration)
end

function ShootAction.serverExecute(player: Player, _playerState: any, directionVector: Vector3?)
	if not directionVector then
		warn(`[ShootAction] Shoot requires directionVector from {player.Name}`)
		return
	end

	local character = player.Character
	if not character then
		warn(`[ShootAction] No character for {player.Name}`)
		return
	end

	local gunTool = GunUtility.findGunTool(character)
	if not gunTool then
		warn(`[ShootAction] No gun tool found for: {player.Name}`)
		return
	end

	local handle = gunTool:FindFirstChild("Handle")
	if not handle then return end

	local shootPoint = handle:FindFirstChild("ShootPoint")
	if not shootPoint then
		warn(`[ShootAction] No ShootPoint attachment on gun handle for: {player.Name}`)
		return
	end

	local origin = shootPoint.WorldPosition
	local direction = directionVector.Unit

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and (origin - rootPart.Position).Magnitude > SharedConfigs.MAX_SHOOT_ORIGIN_DISTANCE then
		warn(`[ShootAction] Shoot origin too far from character for {player.Name}`)
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local result = workspace:Raycast(origin, direction * SharedConfigs.MaxRange, raycastParams)
	local hitPos = result and result.Position or (origin + direction * SharedConfigs.MaxRange)

	drawTracer(origin, hitPos)

	if result then
		local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")
		if hitCharacter then
			local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			if hitPlayer and hitPlayer ~= player and TeleportMetadataService.GetTeam(hitPlayer) ~= TeleportMetadataService.GetTeam(player) then
				local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:SetAttribute("LastDamageSource", player.UserId)
					humanoid:TakeDamage(SharedConfigs.ShootDamage)
				end

				debugPrint(DEBUG, `[ShootAction] {player.Name} shot {hitPlayer.Name}`)

				local remoteName = `GunAction_{player.UserId}`
				NetworkRouter:Call(remoteName, player, {
					payloadType = "ProjectileHitConfirm",
					actionName = "Shoot",
				})
			end
		end
	end
end

function ShootAction.serverCleanup(_player: Player, _playerState: any)
end

return ShootAction
