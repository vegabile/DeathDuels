local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponDistributor = require(script.Parent)

local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
if not knifeModels then
	warn("[WeaponDistributor] ReplicatedStorage.KnifeModels not found")
	return
end

local gunModels = ReplicatedStorage:FindFirstChild("GunModels")
if not gunModels then
	warn("[WeaponDistributor] ReplicatedStorage.GunModels not found")
	return
end

local knife = knifeModels:FindFirstChildWhichIsA("Tool")
if not knife then
	warn("[WeaponDistributor] No Tool found inside KnifeModels")
	return
end

local gun = gunModels:FindFirstChildWhichIsA("Tool")
if not gun then
	warn("[WeaponDistributor] No Tool found inside GunModels")
	return
end

local ok = WeaponDistributor.init(knife, gun)
if not ok then
	warn("[WeaponDistributor] Initialization failed — weapon distribution disabled")
	return
end

local function distribute(player: Player)
	WeaponDistributor.distributeToPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		distribute(player)
	end)
end)

--// Cover players already in-game when this script runs (Studio testing)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function()
		distribute(player)
	end)
	if player.Character then
		distribute(player)
	end
end
