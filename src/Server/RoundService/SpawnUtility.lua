local SPAWN_VERTICAL_CLEARANCE = 3
local SPAWN_LATERAL_SPACING = 5

local SpawnUtility = {}

function SpawnUtility.computeSpawnCFrame(spawnPart: BasePart, occupantIndex: number): CFrame
	local lateral = 0
	if occupantIndex > 0 then
		local step = math.floor((occupantIndex + 1) / 2)
		local sign = if occupantIndex % 2 == 1 then 1 else -1
		lateral = sign * step * SPAWN_LATERAL_SPACING
	end
	local clearance = spawnPart.Size.Y / 2 + SPAWN_VERTICAL_CLEARANCE
	return spawnPart.CFrame * CFrame.new(lateral, clearance, 0)
end

function SpawnUtility.releaseCharacter(player: Player, hrp: BasePart, humanoid: Humanoid, walkSpeed: number)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hrp.Anchored = false
	humanoid.WalkSpeed = walkSpeed
	pcall(function()
		hrp:SetNetworkOwner(player)
	end)
	task.defer(function()
		if hrp.Parent and not hrp.Anchored then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

return SpawnUtility
