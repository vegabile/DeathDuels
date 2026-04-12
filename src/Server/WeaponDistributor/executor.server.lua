local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local WeaponDistributor = require(script.Parent)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local _roundActive = false
ServerEventBus:Connect("RoundStateChanged", function(state)
	_roundActive = (state == RoundConfigs.GAME_STATES.RoundActive)
end)

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

local knives = {}
for _, child in knifeModels:GetChildren() do
	if child:IsA("Tool") then
		table.insert(knives, child)
	end
end

if #knives == 0 then
	warn("[WeaponDistributor] No Tool found inside KnifeModels")
	return
end

local gun = gunModels:FindFirstChildWhichIsA("Tool")
if not gun then
	warn("[WeaponDistributor] No Tool found inside GunModels")
	return
end

local ok = WeaponDistributor.init(knives, gun)
if not ok then
	warn("[WeaponDistributor] Initialization failed — weapon distribution disabled")
	return
end

local function distribute(player: Player)
	if not _roundActive then return end
	local loadout = TeleportMetadataService.GetLoadout(player.UserId)
	local knifeName = loadout and loadout.knifeName
	WeaponDistributor.distributeToPlayer(player, knifeName)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		distribute(player)
	end)
end)

for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function()
		distribute(player)
	end)
	if player.Character then
		distribute(player)
	end
end
