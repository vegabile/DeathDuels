local WeaponConfig = require(game.ReplicatedStorage.WeaponConfig)
local WeaponTypes = require(game.ReplicatedStorage.WeaponTypes)
local NetworkRouter = require(game.ReplicatedStorage.NetworkRouter)
local ServerEventBus = require(script.Parent.ServerEventBus)
local DebugUtility = require(game.ReplicatedStorage.DebugUtility)

type ShotRequest = WeaponTypes.ShotRequest
type GunState = WeaponTypes.GunState
type HitResult = WeaponTypes.HitResult

local CFG = WeaponConfig.Gun
local VAL = WeaponConfig.Validation
local DEBUG = false

local debugPrint = DebugUtility.Print

local GunService = {}
local gunStates: { [Player]: GunState } = {}
local reloading: { [Player]: boolean } = {}

function GunService:GetState(player: Player): GunState
	if not gunStates[player] then
		gunStates[player] = {
			Ammo = CFG.MaxAmmo,
			MaxAmmo = CFG.MaxAmmo,
			LastFiredAt = 0,
		}
	end
	return gunStates[player]
end

local function validateTimestamp(timestamp: number): boolean
	return math.abs(tick() - timestamp) <= VAL.MaxTimestampDrift
end

local function validateOrigin(player: Player, origin: Vector3): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - origin).Magnitude <= VAL.MaxOriginDrift
end

local function validateDirection(direction: Vector3): boolean
	local mag = direction.Magnitude
	return mag > 0.1 and mag < 2
end

local function isHeadshot(hitPart: Instance): boolean
	return hitPart.Name == "Head"
end

local function performRaycast(player: Player, origin: Vector3, direction: Vector3): HitResult
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end

	--// Apply spread
	local spreadRad = math.rad(CFG.SpreadAngle)
	local right = direction:Cross(Vector3.yAxis).Unit
	local up = right:Cross(direction).Unit
	local spreadX = (math.random() - 0.5) * 2 * spreadRad
	local spreadY = (math.random() - 0.5) * 2 * spreadRad
	local spread = CFrame.new(Vector3.zero, direction) * CFrame.Angles(spreadX, spreadY, 0)
	local finalDir = spread.LookVector * CFG.MaxRange

	local result = workspace:Raycast(origin, finalDir, params)
	if not result then
		return {
			Hit = false,
			Position = origin + finalDir,
		}
	end

	local hitPart = result.Instance
	local character = hitPart:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		local targetPlayer = game:GetService("Players"):GetPlayerFromCharacter(character)
		local damage = CFG.Damage
		if isHeadshot(hitPart) then
			damage = damage * CFG.HeadshotMultiplier
		end

		return {
			Hit = true,
			TargetId = targetPlayer and targetPlayer.UserId,
			Position = result.Position,
			Normal = result.Normal,
			Damage = damage,
		}
	end

	return {
		Hit = true,
		Position = result.Position,
		Normal = result.Normal,
	}
end

function GunService:HandleShot(player: Player, request: ShotRequest): (boolean, string?)
	if typeof(request) ~= "table" then
		return false, "Invalid request"
	end
	if typeof(request.Origin) ~= "Vector3" or typeof(request.Direction) ~= "Vector3" then
		return false, "Invalid vectors"
	end
	if typeof(request.Timestamp) ~= "number" then
		return false, "Invalid timestamp"
	end

	if not validateTimestamp(request.Timestamp) then
		return false, "Timestamp drift"
	end
	if not validateOrigin(player, request.Origin) then
		return false, "Origin too far from character"
	end
	if not validateDirection(request.Direction) then
		return false, "Invalid direction"
	end

	if reloading[player] then
		return false, "Reloading"
	end

	local state = self:GetState(player)
	local now = tick()

	if (now - state.LastFiredAt) < CFG.FireRate then
		return false, "Fire rate exceeded"
	end

	if state.Ammo <= 0 then
		return false, "No ammo"
	end

	state.Ammo -= 1
	state.LastFiredAt = now

	debugPrint(DEBUG, `[GunService] {player.Name} fired, ammo: {state.Ammo}/{state.MaxAmmo}`)

	local hitResult = performRaycast(player, request.Origin, request.Direction.Unit)

	if hitResult.TargetId and hitResult.Damage then
		ServerEventBus:Fire("PlayerDamaged", hitResult.TargetId, hitResult.Damage, player)
		debugPrint(DEBUG, `[GunService] Hit player {hitResult.TargetId} for {hitResult.Damage}`)
	end

	--// Broadcast trail to all clients
	NetworkRouter:Call("GunTrail", nil, {
		OwnerId = player.UserId,
		Origin = request.Origin,
		HitPosition = hitResult.Position,
		Hit = hitResult.Hit,
		TargetId = hitResult.TargetId,
	})

	return true
end

function GunService:HandleReload(player: Player): (boolean, string?)
	if reloading[player] then
		return false, "Already reloading"
	end

	local state = self:GetState(player)
	if state.Ammo == state.MaxAmmo then
		return false, "Already full"
	end

	reloading[player] = true
	debugPrint(DEBUG, `[GunService] {player.Name} reloading`)

	task.delay(CFG.ReloadTime, function()
		local currentState = gunStates[player]
		if currentState then
			currentState.Ammo = currentState.MaxAmmo
			debugPrint(DEBUG, `[GunService] {player.Name} reload complete`)
		end
		reloading[player] = nil
		NetworkRouter:Call("GunReloaded", player, { Ammo = CFG.MaxAmmo })
	end)

	return true
end

function GunService:GetAmmo(player: Player): number
	return self:GetState(player).Ammo
end

function GunService:CleanupPlayer(player: Player)
	gunStates[player] = nil
	reloading[player] = nil
end

return GunService
