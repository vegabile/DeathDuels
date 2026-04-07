local WeaponConfig = require(game.ReplicatedStorage.WeaponConfig)
local NetworkRouter = require(game.ReplicatedStorage.NetworkRouter)
local ClientEventBus = require(script.Parent.ClientEventBus)

local Players = game:GetService("Players")

local CFG = WeaponConfig.Knife
local LocalPlayer = Players.LocalPlayer

local KnifeController = {}
local lastThrowTime = 0
local lastStabTime = 0
local predictiveKnives: { [string]: { Part: BasePart, Velocity: Vector3, Alive: boolean } } = {}

local function getCharacterOrigin(): Vector3?
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1.5, 0)
end

local function getAimDirection(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	return camera.CFrame.LookVector
end

--// Predictive knife visual — no authority, purely cosmetic on this client
local function spawnPredictiveKnife(knifeId: string, origin: Vector3, direction: Vector3)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.3, 0.3, 1.8)
	part.Color = Color3.fromRGB(180, 180, 190)
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	part.Parent = workspace

	predictiveKnives[knifeId] = {
		Part = part,
		Velocity = direction.Unit * CFG.ThrowSpeed,
		Alive = true,
	}
end

function KnifeController:StepPredictiveKnives(dt: number)
	for id, knife in predictiveKnives do
		if not knife.Alive then
			continue
		end
		knife.Velocity = knife.Velocity + CFG.Gravity * dt
		local newPos = knife.Part.Position + knife.Velocity * dt
		knife.Part.CFrame = CFrame.lookAt(newPos, newPos + knife.Velocity.Unit)
	end
end

function KnifeController:RemovePredictiveKnife(knifeId: string)
	local knife = predictiveKnives[knifeId]
	if knife then
		knife.Alive = false
		if knife.Part then
			knife.Part:Destroy()
		end
		predictiveKnives[knifeId] = nil
	end
end

function KnifeController:Throw()
	local now = tick()
	if (now - lastThrowTime) < CFG.ThrowCooldown then
		return
	end

	local origin = getCharacterOrigin()
	local direction = getAimDirection()
	if not origin or not direction then
		return
	end

	lastThrowTime = now

	local request = {
		Origin = origin,
		Direction = direction,
		Timestamp = now,
	}

	--// Spawn predictive immediately for responsiveness
	local tempId = "local_" .. tostring(now)
	spawnPredictiveKnife(tempId, origin, direction)

	task.spawn(function()
		local success, knifeId = NetworkRouter:Call("KnifeThrow", request)
		--// Replace local predictive with server-assigned id
		if success and knifeId then
			local old = predictiveKnives[tempId]
			if old then
				predictiveKnives[knifeId] = old
				predictiveKnives[tempId] = nil
			end
		else
			self:RemovePredictiveKnife(tempId)
		end
	end)
end

function KnifeController:Stab()
	local now = tick()
	if (now - lastStabTime) < CFG.StabCooldown then
		return
	end

	local character = LocalPlayer.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	--// Find nearest target in stab range
	local closestId = nil
	local closestDist = CFG.StabRange

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == LocalPlayer then
			continue
		end
		local otherChar = otherPlayer.Character
		if not otherChar then
			continue
		end
		local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
		if not otherRoot then
			continue
		end
		local dist = (root.Position - otherRoot.Position).Magnitude
		if dist < closestDist then
			closestDist = dist
			closestId = otherPlayer.UserId
		end
	end

	if not closestId then
		return
	end

	lastStabTime = now
	ClientEventBus:Fire("KnifeStabVisual")

	NetworkRouter:Call("KnifeStab", {
		TargetId = closestId,
		Timestamp = now,
	})
end

--// Server tells us a knife hit something — remove predictive, show impact
function KnifeController:OnKnifeHit(data)
	self:RemovePredictiveKnife(data.KnifeId)
	ClientEventBus:Fire("KnifeHitVisual", data.Position, data.Normal, data.TargetId)
end

--// Server tells us a knife stuck into a surface
function KnifeController:OnKnifeStuck(data)
	self:RemovePredictiveKnife(data.KnifeId)
	ClientEventBus:Fire("KnifeStuckVisual", data.Position, data.Normal)
end

function KnifeController:Init()
	NetworkRouter:Listen("KnifeHit", function(data)
		self:OnKnifeHit(data)
	end)

	NetworkRouter:Listen("KnifeStuck", function(data)
		self:OnKnifeStuck(data)
	end)

	--// Other players' predictive knives
	NetworkRouter:Listen("KnifeThrown", function(data)
		if data.OwnerId == LocalPlayer.UserId then
			return
		end
		spawnPredictiveKnife(data.KnifeId, data.Origin, data.Direction)
	end)

	game:GetService("RunService").Heartbeat:Connect(function(dt)
		self:StepPredictiveKnives(dt)
	end)
end

return KnifeController
