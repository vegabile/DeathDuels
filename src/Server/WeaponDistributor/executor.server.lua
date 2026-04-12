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

local function validateWeapons(): (boolean, { string }?, { Tool }?, { Tool }?)
	local problems = {}
	local knives = {}
	local guns = {}

	local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
	if not knifeModels then
		table.insert(problems, "ReplicatedStorage.KnifeModels missing")
	else
		for _, child in knifeModels:GetChildren() do
			if child:IsA("Tool") then
				table.insert(knives, child)
			else
				table.insert(
					problems,
					`KnifeModels.{child.Name} is not a Tool (got {child.ClassName})`
				)
			end
		end
		if #knives == 0 then
			table.insert(problems, "KnifeModels contains zero Tools")
		end
	end

	local gunModels = ReplicatedStorage:FindFirstChild("GunModels")
	if not gunModels then
		table.insert(problems, "ReplicatedStorage.GunModels missing")
	else
		for _, child in gunModels:GetChildren() do
			if child:IsA("Tool") then
				table.insert(guns, child)
			else
				table.insert(
					problems,
					`GunModels.{child.Name} is not a Tool (got {child.ClassName})`
				)
			end
		end
		if #guns == 0 then
			table.insert(problems, "GunModels contains zero Tools")
		end
	end

	if #problems > 0 then
		return false, problems, nil, nil
	end
	return true, nil, knives, guns
end

local validationOk, problems, knives, guns = validateWeapons()
if not validationOk then
	warn("[WeaponDistributor] CRITICAL — weapon validation failed:")
	for _, msg in problems do
		warn(`  - {msg}`)
	end
	ServerEventBus:Fire("WeaponSystemReady", false)
	return
end

local initOk = WeaponDistributor.init(knives, guns)
if not initOk then
	warn("[WeaponDistributor] CRITICAL — init failed")
	ServerEventBus:Fire("WeaponSystemReady", false)
	return
end

ServerEventBus:Fire("WeaponSystemReady", true)

local function distribute(player: Player)
	if not _roundActive then return end
	local loadout = TeleportMetadataService.GetLoadout(player.UserId)
	local knifeName = loadout and loadout.knifeName
	local gunName = loadout and loadout.gunName
	WeaponDistributor.distributeToPlayer(player, knifeName, gunName)
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
