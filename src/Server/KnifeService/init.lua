local WeaponConfig = require(game.ReplicatedStorage.WeaponConfig)
local WeaponTypes = require(game.ReplicatedStorage.WeaponTypes)
local NetworkRouter = require(game.ReplicatedStorage.NetworkRouter)
local ServerEventBus = require(script.Parent.ServerEventBus)
local DebugUtility = require(game.ReplicatedStorage.DebugUtility)

type ThrowRequest = WeaponTypes.ThrowRequest
type StabRequest = WeaponTypes.StabRequest
type KnifeState = WeaponTypes.KnifeState
type HitResult = WeaponTypes.HitResult

local CFG = WeaponConfig.Knife
local VAL = WeaponConfig.Validation
local DEBUG = false

local debugPrint = DebugUtility.Print

local KnifeService = {}
local activeKnives: { [string]: KnifeState } = {}
local cooldowns: { [Player]: number } = {}

local function generateId(): string
	return game:GetService("HttpService"):GenerateGUID(false)
end

local function isOnCooldown(player: Player, cooldownTime: number): boolean
	local last = cooldowns[player]
	if not last then
		return false
	end
	return (tick() - last) < cooldownTime
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

local function raycastKnife(origin: Vector3, direction: Vector3): HitResult
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}

	local result = workspace:Raycast(origin, direction, params)
	if not result then
		return { Hit = false }
	end

	local hitPart = result.Instance
	local character = hitPart:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		local targetPlayer = game:GetService("Players"):GetPlayerFromCharacter(character)
		return {
			Hit = true,
			TargetId = targetPlayer and targetPlayer.UserId,
			Position = result.Position,
			Normal = result.Normal,
			Damage = CFG.ThrowDamage,
		}
	end

	return {
		Hit = true,
		Position = result.Position,
		Normal = result.Normal,
	}
end

--// Server-authoritative knife projectile: steps through arc per dt, raycasts each segment
function KnifeService:SimulateThrow(knifeId: string, state: KnifeState, onHit: (HitResult) -> (), onStick: (Vector3, Vector3, Instance?) -> ())
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local owner = state.Owner
	if owner and owner.Character then
		params.FilterDescendantsInstances = { owner.Character }
	end

	local position = state.Position
	local velocity = state.Velocity
	local elapsed = 0
	local maxTime = CFG.ThrowMaxDistance / CFG.ThrowSpeed

	while elapsed < maxTime and elapsed < CFG.LifetimeSeconds do
		local dt = 1 / 60
		local gravity = CFG.Gravity * dt
		velocity = velocity + gravity
		local step = velocity * dt
		local result = workspace:Raycast(position, step, params)

		if result then
			local hitPart = result.Instance
			local character = hitPart:FindFirstAncestorOfClass("Model")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if humanoid and humanoid.Health > 0 then
				local targetPlayer = game:GetService("Players"):GetPlayerFromCharacter(character)
				onHit({
					Hit = true,
					TargetId = targetPlayer and targetPlayer.UserId,
					Position = result.Position,
					Normal = result.Normal,
					Damage = CFG.ThrowDamage,
				})
				activeKnives[knifeId] = nil
				return
			end

			--// Hit world geometry — stick into surface
			onStick(result.Position, result.Normal, hitPart)
			activeKnives[knifeId] = nil
			return
		end

		position = position + step
		elapsed += dt
	end

	--// Fell out of range with no collision
	activeKnives[knifeId] = nil
end

function KnifeService:HandleThrow(player: Player, request: ThrowRequest): (boolean, string?)
	if typeof(request) ~= "table" then
		return false, "Invalid request"
	end
	if typeof(request.Origin) ~= "Vector3" or typeof(request.Direction) ~= "Vector3" then
		return false, "Invalid vectors"
	end
	if typeof(request.Timestamp) ~= "number" then
		return false, "Invalid timestamp"
	end

	if isOnCooldown(player, CFG.ThrowCooldown) then
		return false, "On cooldown"
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

	cooldowns[player] = tick()
	local direction = request.Direction.Unit
	local velocity = direction * CFG.ThrowSpeed
	local knifeId = generateId()

	local state: KnifeState = {
		Owner = player,
		Position = request.Origin,
		Velocity = velocity,
		Stuck = false,
		StuckTo = nil,
		Elapsed = 0,
	}
	activeKnives[knifeId] = state

	debugPrint(DEBUG, `[KnifeService] {player.Name} threw knife {knifeId}`)

	--// Broadcast to all clients for predictive visuals
	NetworkRouter:Call("KnifeThrown", nil, {
		KnifeId = knifeId,
		OwnerId = player.UserId,
		Origin = request.Origin,
		Direction = direction,
		Speed = CFG.ThrowSpeed,
	})

	task.spawn(function()
		self:SimulateThrow(knifeId, state, function(hitResult: HitResult)
			if hitResult.TargetId then
				ServerEventBus:Fire("PlayerDamaged", hitResult.TargetId, hitResult.Damage, player)
				debugPrint(DEBUG, `[KnifeService] Knife {knifeId} hit player {hitResult.TargetId} for {hitResult.Damage}`)
			end
			NetworkRouter:Call("KnifeHit", nil, {
				KnifeId = knifeId,
				Position = hitResult.Position,
				Normal = hitResult.Normal,
				TargetId = hitResult.TargetId,
			})
		end, function(position: Vector3, normal: Vector3, stuckTo: Instance?)
			debugPrint(DEBUG, `[KnifeService] Knife {knifeId} stuck at {position}`)
			NetworkRouter:Call("KnifeStuck", nil, {
				KnifeId = knifeId,
				Position = position,
				Normal = normal,
			})
		end)
	end)

	return true, knifeId
end

function KnifeService:HandleStab(player: Player, request: StabRequest): (boolean, string?)
	if typeof(request) ~= "table" then
		return false, "Invalid request"
	end
	if typeof(request.TargetId) ~= "number" then
		return false, "Invalid target"
	end
	if typeof(request.Timestamp) ~= "number" then
		return false, "Invalid timestamp"
	end

	if isOnCooldown(player, CFG.StabCooldown) then
		return false, "On cooldown"
	end
	if not validateTimestamp(request.Timestamp) then
		return false, "Timestamp drift"
	end

	local character = player.Character
	if not character then
		return false, "No character"
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "No root part"
	end

	local targetPlayer = game:GetService("Players"):GetPlayerByUserId(request.TargetId)
	if not targetPlayer or not targetPlayer.Character then
		return false, "Target not found"
	end
	local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return false, "Target has no root"
	end

	local distance = (root.Position - targetRoot.Position).Magnitude
	if distance > CFG.StabRange then
		return false, "Out of range"
	end

	local targetHumanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false, "Target already dead"
	end

	cooldowns[player] = tick()
	debugPrint(DEBUG, `[KnifeService] {player.Name} stabbed {targetPlayer.Name} for {CFG.StabDamage}`)
	ServerEventBus:Fire("PlayerDamaged", request.TargetId, CFG.StabDamage, player)

	return true
end

function KnifeService:GetActiveKnives(): { [string]: KnifeState }
	return activeKnives
end

function KnifeService:CleanupPlayer(player: Player)
	cooldowns[player] = nil
	for id, state in activeKnives do
		if state.Owner == player then
			activeKnives[id] = nil
		end
	end
end

return KnifeService
