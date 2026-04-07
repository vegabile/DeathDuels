local WeaponConfig = require(game.ReplicatedStorage.WeaponConfig)
local NetworkRouter = require(game.ReplicatedStorage.NetworkRouter)
local ClientEventBus = require(script.Parent.ClientEventBus)

local Players = game:GetService("Players")

local CFG = WeaponConfig.Gun
local LocalPlayer = Players.LocalPlayer

local GunController = {}
local ammo = CFG.MaxAmmo
local lastFireTime = 0
local isReloading = false

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

local function drawTrail(origin: Vector3, hitPosition: Vector3)
	local distance = (hitPosition - origin).Magnitude
	local mid = (origin + hitPosition) / 2

	local trail = Instance.new("Part")
	trail.Size = Vector3.new(0.05, 0.05, distance)
	trail.CFrame = CFrame.lookAt(mid, hitPosition)
	trail.Anchored = true
	trail.CanCollide = false
	trail.Material = Enum.Material.Neon
	trail.Color = CFG.TrailColor
	trail.Transparency = 0.3
	trail.Parent = workspace

	task.delay(CFG.TrailLifetime, function()
		trail:Destroy()
	end)
end

function GunController:Shoot()
	local now = tick()
	if (now - lastFireTime) < CFG.FireRate then
		return
	end
	if isReloading then
		return
	end
	if ammo <= 0 then
		ClientEventBus:Fire("GunEmpty")
		return
	end

	local origin = getCharacterOrigin()
	local direction = getAimDirection()
	if not origin or not direction then
		return
	end

	lastFireTime = now
	ammo -= 1
	ClientEventBus:Fire("AmmoChanged", ammo, CFG.MaxAmmo)

	NetworkRouter:Call("GunShoot", {
		Origin = origin,
		Direction = direction,
		Timestamp = now,
	})
end

function GunController:Reload()
	if isReloading then
		return
	end
	if ammo == CFG.MaxAmmo then
		return
	end

	isReloading = true
	ClientEventBus:Fire("ReloadStarted")

	NetworkRouter:Call("GunReload")
end

function GunController:GetAmmo(): (number, number)
	return ammo, CFG.MaxAmmo
end

function GunController:Init()
	NetworkRouter:Listen("GunTrail", function(data)
		if data.Origin and data.HitPosition then
			drawTrail(data.Origin, data.HitPosition)
		end
		if data.TargetId then
			ClientEventBus:Fire("GunHitMarker", data.TargetId)
		end
	end)

	NetworkRouter:Listen("GunReloaded", function(data)
		ammo = data.Ammo
		isReloading = false
		ClientEventBus:Fire("AmmoChanged", ammo, CFG.MaxAmmo)
		ClientEventBus:Fire("ReloadFinished")
	end)
end

return GunController
