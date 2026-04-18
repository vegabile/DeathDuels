local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Gun.Configs)
local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local AnimationsConfigs = require(game:GetService("ReplicatedStorage").Animations.Configs)
local ServerConfigs = require(script.Parent.Parent.Configs)
local TeleportMetadataService = require(script.Parent.Parent.Parent.RoundService.TeleportMetadataService)
local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local ShootAction = {}

ShootAction.name = "Shoot"
ShootAction.cooldown = SharedConfigs.ShootCooldown
ShootAction.duration = SharedConfigs.ShootDuration
do
	local _profile = AnimationProfile.resolve("SmallPistol", SharedConfigs.AnimationProfiles, AnimationType.Shoot)
	ShootAction.animationId = (_profile and _profile.id) or ""
end

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

function ShootAction.serverExecute(
	player: Player,
	_playerState: any,
	directionVector: Vector3?,
	restOrigin: Vector3?
)
	if not directionVector then
		warn(`[ShootAction] missing directionVector for {player.Name}`)
		return
	end
	if not restOrigin then
		warn(`[ShootAction] missing restOrigin for {player.Name}`)
		return
	end

	local character = player.Character
	if not character then
		warn(`[ShootAction] no character for {player.Name}`)
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		warn(`[ShootAction] no HumanoidRootPart for {player.Name}`)
		return
	end

	if (restOrigin - rootPart.Position).Magnitude > AnimationsConfigs.MaxRestOriginDistance then
		warn(`[ShootAction] restOrigin out of range for {player.Name}`)
		return
	end

	local direction = directionVector.Unit
	local origin = restOrigin

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
			if hitPlayer and hitPlayer ~= player
				and TeleportMetadataService.GetTeam(hitPlayer) ~= TeleportMetadataService.GetTeam(player)
			then
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
