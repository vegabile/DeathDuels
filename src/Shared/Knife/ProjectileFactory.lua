local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local Types = require(script.Parent.Types)

local DEBUG = SharedConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local ProjectileFactory = {}

function ProjectileFactory.stick(projectile: BasePart, hitPosition: Vector3?)
	local lv = projectile:FindFirstChildOfClass("LinearVelocity")
	local av = projectile:FindFirstChildOfClass("AngularVelocity")
	if lv then lv:Destroy() end
	if av then av:Destroy() end
	if hitPosition then
		projectile.CFrame = CFrame.new(hitPosition)
	end
	projectile.Anchored = true
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

	local clonedHandle = handle:Clone()
	clonedHandle.Transparency = config.transparency
	clonedHandle.CanCollide = false
	clonedHandle.CFrame = config.spawnCFrame
	clonedHandle.Parent = config.parent

	local attachment = Instance.new("Attachment")
	attachment.Parent = clonedHandle

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = config.directionVector * SharedConfigs.ThrowSpeed
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = clonedHandle

	local angularVelocity = Instance.new("AngularVelocity")
	angularVelocity.MaxTorque = math.huge
	angularVelocity.AngularVelocity = Vector3.new(math.pi * 4, 0, 0)
	angularVelocity.Attachment0 = attachment
	angularVelocity.Parent = clonedHandle

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

	local lastPosition = clonedHandle.Position
	local alreadyHitFromThrow: { [Player]: boolean } = {}
	local stuck = false
	local heartbeatConnection: RBXScriptConnection

	local function stickAndCleanup(hitPosition: Vector3?)
		stuck = true
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
		end
		ProjectileFactory.stick(clonedHandle, hitPosition)
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
			local result = workspace:Raycast(lastPosition, delta, raycastParams)

			if result then
				local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")

				if hitCharacter then
					local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
					if hitPlayer and hitPlayer ~= owner and not alreadyHitFromThrow[hitPlayer] then
						alreadyHitFromThrow[hitPlayer] = true
						stickAndCleanup(result.Position)
						if onHit then
							onHit(hitPlayer)
						end
					end
				else
					stickAndCleanup(result.Position)
				end
			end
		end

		lastPosition = currentPosition
	end)

	Debris:AddItem(clonedHandle, SharedConfigs.ProjectileMaxLifetime)

	return clonedHandle
end

return ProjectileFactory
