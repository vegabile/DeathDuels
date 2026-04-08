local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local Types = require(script.Parent.Types)

local DEBUG = SharedConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

--// How far (studs) to embed the knife tip into the surface on stick
local EMBED_DEPTH = 0.5
--// End-over-end tumble rate (rad/s) — matches the old AngularVelocity feel
local SPIN_RATE = math.pi * 4
--// Overlap params for the secondary GetPartsInPart check
local OVERLAP_PARAMS_FILTER_TYPE = Enum.RaycastFilterType.Exclude

local ProjectileFactory = {}

--[[
	Stick the projectile into a surface.
	- travelDirection: the normalized direction the knife was moving at impact
	- hitPosition: world-space hit point
	- hitNormal: surface normal at the hit point (optional, used for embed offset)
	
	The knife is oriented so its front axis (negative Z in Roblox convention) points
	along the travel direction, then nudged into the surface by EMBED_DEPTH studs.
]]
function ProjectileFactory.stick(
	projectile: BasePart,
	travelDirection: Vector3?,
	hitPosition: Vector3?,
	hitNormal: Vector3?
)
	local lv = projectile:FindFirstChildOfClass("LinearVelocity")
	local av = projectile:FindFirstChildOfClass("AngularVelocity")
	if lv then lv:Destroy() end
	if av then av:Destroy() end

	if hitPosition and travelDirection then
		--// Orient the knife along its travel direction.
		--// CFrame.new(pos, pos + dir) points -Z toward the target, so the
		--// knife's front face aims along the flight path.
		local embedOffset = travelDirection * EMBED_DEPTH
		local stickPos = hitPosition + embedOffset
		projectile.CFrame = CFrame.new(stickPos, stickPos + travelDirection)
	elseif hitPosition then
		projectile.CFrame = CFrame.new(hitPosition)
	end

	projectile.Anchored = true
	projectile.CanCollide = false
	Debris:AddItem(projectile, SharedConfigs.StuckDespawnTime)
end

function ProjectileFactory.spawnProjectile(
	config: Types.ProjectileConfig,
	owner: Player,
	blacklist: { Instance }?,
	onHit: ((hitPlayer: Player) -> ())?
): BasePart?
	local handle = config.template:FindFirstChild("Handle")
	if not handle then
		warn("[ProjectileFactory] No Handle found in template")
		return nil
	end

	local direction = config.directionVector.Unit

	local clonedHandle = handle:Clone()
	clonedHandle.Transparency = config.transparency
	clonedHandle.CanCollide = false

	--// Orient the knife so its front (-Z) faces the throw direction from the start
	clonedHandle.CFrame = CFrame.new(config.spawnCFrame.Position, config.spawnCFrame.Position + direction)
	clonedHandle.Parent = config.parent

	local attachment = Instance.new("Attachment")
	attachment.Parent = clonedHandle

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = direction * SharedConfigs.ThrowSpeed
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = clonedHandle

	--// Tumble end-over-end around the knife's LOCAL right axis (X).
	--// Because the knife is already oriented along the throw direction,
	--// spinning on local X gives a realistic forward tumble.
	local angularVelocity = Instance.new("AngularVelocity")
	angularVelocity.MaxTorque = math.huge
	angularVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	angularVelocity.AngularVelocity = Vector3.new(math.pi * 4, 0, 0)
	angularVelocity.Attachment0 = attachment
	angularVelocity.Parent = clonedHandle

	--// Build exclude list for raycasts and overlap checks
	local excludeList = {}
	if blacklist then
		for _, inst in blacklist do
			table.insert(excludeList, inst)
		end
	end
	table.insert(excludeList, clonedHandle)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludeList

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = OVERLAP_PARAMS_FILTER_TYPE
	overlapParams.FilterDescendantsInstances = excludeList

	local lastPosition = clonedHandle.Position
	local alreadyHitFromThrow: { [Player]: boolean } = {}
	local stuck = false
	local heartbeatConnection: RBXScriptConnection

	local function stickAndCleanup(hitPosition: Vector3?, hitNormal: Vector3?)
		stuck = true
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
		end
		ProjectileFactory.stick(clonedHandle, direction, hitPosition, hitNormal)
	end

	local function processHit(result: RaycastResult)
		local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")

		if hitCharacter then
			local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			if hitPlayer and hitPlayer ~= owner and not alreadyHitFromThrow[hitPlayer] then
				alreadyHitFromThrow[hitPlayer] = true
				stickAndCleanup(result.Position, result.Normal)
				if onHit then
					onHit(hitPlayer)
				end
				return true
			end
			--// Hit own character or already-hit player — ignore, keep flying
			return false
		else
			--// Non-player geometry — stick into it
			stickAndCleanup(result.Position, result.Normal)
			return true
		end
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if stuck or not clonedHandle.Parent then
			debugPrint(DEBUG, `[ProjectileFactory] Exiting heartbeat — stuck={stuck}, parent={clonedHandle.Parent}`)
			heartbeatConnection:Disconnect()
			return
		end

		local currentPosition = clonedHandle.Position
		local delta = currentPosition - lastPosition

		if delta.Magnitude > 0 then
			--// Primary detection: raycast from last position with lookahead
			--// The lookahead catches high-speed misses where the knife moves
			--// further than one frame's delta in a single step.
			local rayDirection = delta * RAYCAST_LOOKAHEAD
			local result = workspace:Raycast(lastPosition, rayDirection, raycastParams)

			if result then
				local handled = processHit(result)
				if handled then
					lastPosition = currentPosition
					return
				end
			end

			--// Secondary detection: overlap check at current position.
			--// Catches thin/small parts the raycast may thread through,
			--// and objects the knife is already inside.
			local touching = workspace:GetPartsInPart(clonedHandle, overlapParams)
			if #touching > 0 then
				for _, part in touching do
					--// Skip parts that are in the exclude list conceptually
					--// (other projectiles, effects, etc.)
					if part.CanCollide or part:GetAttribute("KnifeCollidable") then
						local partCharacter = part:FindFirstAncestorOfClass("Model")
						if partCharacter then
							local hitPlayer = Players:GetPlayerFromCharacter(partCharacter)
							if hitPlayer and hitPlayer ~= owner and not alreadyHitFromThrow[hitPlayer] then
								alreadyHitFromThrow[hitPlayer] = true
								stickAndCleanup(currentPosition, nil)
								if onHit then
									onHit(hitPlayer)
								end
								lastPosition = currentPosition
								return
							end
						else
							--// Non-player collidable part — stick
							stickAndCleanup(currentPosition, nil)
							lastPosition = currentPosition
							return
						end
					end
				end
			end
		end

		lastPosition = currentPosition
	end)

	Debris:AddItem(clonedHandle, SharedConfigs.ProjectileMaxLifetime)

	return clonedHandle
end

return ProjectileFactory
