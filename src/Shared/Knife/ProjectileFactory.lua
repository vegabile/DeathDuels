local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local Types = require(script.Parent.Types)

local function knifeTrace(message: string)
	print("[KNIFE] [ProjectileFactory] " .. message)
end

--// How far (studs) to embed the knife tip into the surface on stick
local EMBED_DEPTH = 0.5
--// End-over-end tumble rate (rad/s) matches the old AngularVelocity feel
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
	knifeTrace("[ProjectileFactory] stick called")
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
	knifeTrace(`[ProjectileFactory] spawnProjectile start owner={owner.Name}`)
	local handle = config.template:FindFirstChild("Handle")
	if not handle then
		warn("[KNIFE] [ProjectileFactory] No Handle found in template")
		return nil
	end
	knifeTrace(`[ProjectileFactory] handle={handle.Name} template={config.template:GetFullName()}`)

	local direction = config.directionVector.Unit
	knifeTrace(`[ProjectileFactory] direction={direction}`)

	local clonedHandle = handle:Clone()
	clonedHandle.Transparency = config.transparency
	clonedHandle.CanCollide = false

	--// Orient the knife so its front (-Z) faces the throw direction from the start
	clonedHandle.CFrame = CFrame.new(config.spawnCFrame.Position, config.spawnCFrame.Position + direction)
	clonedHandle.Parent = config.parent
	knifeTrace(`[ProjectileFactory] spawned handle parent={config.parent:GetFullName()} pos={clonedHandle.Position}`)

	local attachment = Instance.new("Attachment")
	attachment.Parent = clonedHandle

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = direction * SharedConfigs.ThrowSpeed
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = clonedHandle

	--// Build exclude list for raycasts and overlap checks
	local excludeList = {}
	local excludeSet: { [Instance]: boolean } = {}

	local function addExcluded(inst: Instance?)
		if not inst or excludeSet[inst] then
			return
		end
		excludeSet[inst] = true
		table.insert(excludeList, inst)
	end

	if blacklist then
		for _, inst in blacklist do
			addExcluded(inst)
		end
	end
	addExcluded(clonedHandle)
	knifeTrace(`[ProjectileFactory] excludeList size={#excludeList}`)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludeList

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = OVERLAP_PARAMS_FILTER_TYPE
	overlapParams.FilterDescendantsInstances = excludeList

	local function refreshDynamicExcludes()
		--// The authoritative server projectile folder can appear after a client cosmetic
		--// projectile is spawned on the first throw. Refreshing here keeps the ignore
		--// list current instead of freezing the startup state forever.
		addExcluded(workspace:FindFirstChild("KnifeIgnoreFolder"))
		raycastParams.FilterDescendantsInstances = excludeList
		overlapParams.FilterDescendantsInstances = excludeList
	end

	local spawnOrigin = clonedHandle.Position
	local alreadyHitFromThrow: { [Player]: boolean } = {}
	local stuck = false
	local elapsedTime = 0
	local heartbeatConnection: RBXScriptConnection
	local tickCount = 0

	local function stickAndCleanup(hitPosition: Vector3?, hitNormal: Vector3?)
		knifeTrace(`[ProjectileFactory] stickAndCleanup called hitPosition={hitPosition}`)
		if stuck then
			knifeTrace("[ProjectileFactory] stickAndCleanup ignored because already stuck")
			return
		end
		stuck = true
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
		end
		ProjectileFactory.stick(clonedHandle, direction, hitPosition, hitNormal)
	end

	local function processHit(result: RaycastResult)
		knifeTrace(`[ProjectileFactory] processHit on={result.Instance:GetFullName()}`)
		local hitModel = result.Instance:FindFirstAncestorOfClass("Model")

		if hitModel then
			local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
			if hitPlayer then
				if hitPlayer ~= owner and not alreadyHitFromThrow[hitPlayer] then
					alreadyHitFromThrow[hitPlayer] = true
					stickAndCleanup(result.Position, result.Normal)
					if onHit then
						onHit(hitPlayer)
					end
					knifeTrace(`[ProjectileFactory] hit player={hitPlayer.Name}`)
					return true
				end
				knifeTrace(`[ProjectileFactory] ignored hit on ineligible player for {owner.Name}`)
				return false
			end

			--// Non-player model geometry - stick into it.
			stickAndCleanup(result.Position, result.Normal)
			knifeTrace(`[ProjectileFactory] hit non-player model geometry={hitModel:GetFullName()}`)
			return true
		else
			--// Non-model geometry - stick into it.
			stickAndCleanup(result.Position, result.Normal)
			knifeTrace(`[ProjectileFactory] hit geometry={result.Instance:GetFullName()}`)
			return true
		end
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		tickCount += 1
		if stuck or not clonedHandle.Parent then
			knifeTrace(`[ProjectileFactory] heartbeat exit stuck={stuck} parent={clonedHandle.Parent}`)
			heartbeatConnection:Disconnect()
			return
		end

		elapsedTime += dt
		local currentPosition = clonedHandle.Position

		--// Deterministic tumble: re-assert flight-direction orientation + end-over-end spin
		local baseCFrame = CFrame.new(currentPosition, currentPosition + direction)
		clonedHandle.CFrame = baseCFrame * CFrame.Angles(elapsedTime * SPIN_RATE, 0, 0)
		if tickCount == 1 or tickCount % 10 == 0 then
			knifeTrace(`[ProjectileFactory] heartbeat tick={tickCount} dt={dt} elapsed={elapsedTime}`)
		end

		refreshDynamicExcludes()

		--// Primary detection: continuous raycast from spawn origin to current position.
		--// Covers the entire flight path every frame - thin walls cannot be skipped.
		local toCurrentPos = currentPosition - spawnOrigin
		if toCurrentPos.Magnitude > 0 then
			local result = workspace:Raycast(spawnOrigin, toCurrentPos, raycastParams)
			if result then
				knifeTrace(`[ProjectileFactory] raycast hit instance={result.Instance:GetFullName()}`)
				local handled = processHit(result)
				if handled then
					return
				end
			end
		end

		--// Secondary detection: overlap check for player character hits.
		--// Characters have complex multi-part geometry that benefits from overlap checks.
		local touching = workspace:GetPartsInPart(clonedHandle, overlapParams)
		if #touching > 0 then
			knifeTrace(`[ProjectileFactory] overlap count={#touching}`)
			for _, part in touching do
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
							knifeTrace(`[ProjectileFactory] overlap hit player={hitPlayer.Name}`)
							return
						end
						if not hitPlayer then
							stickAndCleanup(currentPosition, nil)
							knifeTrace(`[ProjectileFactory] overlap hit non-player model geometry={partCharacter:GetFullName()}`)
							return
						end
					else
						stickAndCleanup(currentPosition, nil)
						knifeTrace(`[ProjectileFactory] overlap hit geometry={part:GetFullName()}`)
						return
					end
				end
			end
		end
	end)

	Debris:AddItem(clonedHandle, SharedConfigs.ProjectileMaxLifetime)

	knifeTrace(`[ProjectileFactory] returning handle={clonedHandle.Name}`)
	return clonedHandle
end

return ProjectileFactory
