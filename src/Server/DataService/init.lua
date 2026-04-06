local Types = require(script.Types)
type DataSchema = Types.DataSchema

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ProfileStore = require(script.ProfileService)
local DebugUtility = require(game.ReplicatedStorage.DebugUtility)
local Configs = require(script.Configs)

local DEBUG = Configs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local DEFAULT_SCHEMA: DataSchema = {
	Coin = 0,
	Knives = {},
	Guns = {},
}

local PlayerStore = ProfileStore.New("PlayerData", DEFAULT_SCHEMA)
local Profiles: { [Player]: typeof(PlayerStore:StartSessionAsync("")) } = {}

debugPrint(DEBUG, "[DataService] Module initialized, PlayerStore created")

local DataService = {}

function DataService.GetProfile(player: Player)
	debugPrint(DEBUG, `[DataService] GetProfile called for {player.Name}`)
	return Profiles[player]
end

function DataService.GetData(player: Player): DataSchema?
	debugPrint(DEBUG, `[DataService] GetData called for {player.Name}`)
	local profile = Profiles[player]
	if profile then
		return profile.Data
	end
	debugPrint(DEBUG, `[DataService] No profile found for {player.Name}`)
	return nil
end

function DataService.OnPlayerAdded(player: Player)
	debugPrint(DEBUG, `[DataService] OnPlayerAdded starting for {player.Name} ({player.UserId})`)

	local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`)

	if profile == nil then
		debugPrint(DEBUG, `[DataService] Failed to load profile for {player.Name}, kicking`)
		player:Kick("Unable to load your data. Please rejoin.")
		return
	end

	debugPrint(DEBUG, `[DataService] Profile loaded for {player.Name}`)

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	debugPrint(DEBUG, `[DataService] Reconciled profile for {player.Name}`)

	profile.OnSessionEnd:Connect(function()
		debugPrint(DEBUG, `[DataService] Session ended for {player.Name}, clearing profile`)
		Profiles[player] = nil
		player:Kick("Your data session ended. Please rejoin.")
	end)

	if player:IsDescendantOf(Players) then
		Profiles[player] = profile
		debugPrint(DEBUG, `[DataService] Profile stored for {player.Name}`)
	else
		debugPrint(DEBUG, `[DataService] {player.Name} left before profile loaded, ending session`)
		profile:EndSession()
	end
end

function DataService.OnPlayerRemoving(player: Player)
	debugPrint(DEBUG, `[DataService] OnPlayerRemoving for {player.Name}`)
	local profile = Profiles[player]
	if profile then
		debugPrint(DEBUG, `[DataService] Ending session for {player.Name}`)
		profile:EndSession()
	end
end

function DataService._modifyCoinsAfterEffects(player : Player, newCoinAmount : number)
	debugPrint(DEBUG, `[DataService] _modifyCoinsAfterEffects called for {player.Name} with newCoinAmount: {newCoinAmount}`)
	-- Placeholder for any additional logic that should run after modifying coins
end

function DataService._modifyCoins(player : Player, newCoinAmount : number) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] _modifyCoins called for {player.Name} with newCoinAmount: {newCoinAmount}`)
	local profile = Profiles[player]
	if profile then
		profile.Data.Coin = newCoinAmount
		debugPrint(DEBUG, `[DataService] Coin amount updated for {player.Name} to {newCoinAmount}`)
		DataService._modifyCoinsAfterEffects(player, newCoinAmount)
		return {
			successful = true,
			errorMessage = nil,
		}
	else
		debugPrint(DEBUG, `[DataService] Failed to modify coins for {player.Name}, no profile found`)
		return {
			successful = false,
			errorMessage = "Profile not found",
		}
	end
end

function DataService.AddCoins(player : Player, amount : number) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] AddCoins called for {player.Name} with amount: {amount}`)
	local data = DataService.GetData(player)
	if not data then
		return { successful = false, errorMessage = "Profile not found" }
	end
	return DataService._modifyCoins(player, data.Coin + amount)
end

function DataService.RemoveCoins(player : Player, amount : number) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] RemoveCoins called for {player.Name} with amount: {amount}`)
	local data = DataService.GetData(player)
	if not data then
		return { successful = false, errorMessage = "Profile not found" }
	end
	if data.Coin < amount then
		warn(`[DataService] Insufficient coins for {player.Name}: has {data.Coin}, needs {amount}`)
		return { successful = false, errorMessage = "Insufficient coins" }
	end
	return DataService._modifyCoins(player, data.Coin - amount)
end

function DataService._modifyKnivesAfterEffects(player : Player, knives : { Types.KnifeSchema })
	debugPrint(DEBUG, `[DataService] _modifyKnivesAfterEffects called for {player.Name}`)
end

function DataService.GetKnifeById(player : Player, knifeId : string) : Types.KnifeSchema?
	local data = DataService.GetData(player)
	if not data then return nil end
	for _, knife in data.Knives do
		if knife.id == knifeId then
			return knife
		end
	end
	return nil
end

function DataService.AddKnife(player : Player, knifeName : string) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] AddKnife called for {player.Name} with name: {knifeName}`)
	local profile = Profiles[player]
	if not profile then
		return { successful = false, errorMessage = "Profile not found" }
	end
	local knife : Types.KnifeSchema = {
		id = HttpService:GenerateGUID(false),
		name = knifeName,
		equipped = false,
	}
	table.insert(profile.Data.Knives, knife)
	DataService._modifyKnivesAfterEffects(player, profile.Data.Knives)
	return { successful = true, errorMessage = nil }
end

function DataService.RemoveKnife(player : Player, knifeId : string) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] RemoveKnife called for {player.Name} with id: {knifeId}`)
	local profile = Profiles[player]
	if not profile then
		return { successful = false, errorMessage = "Profile not found" }
	end
	for i, knife in profile.Data.Knives do
		if knife.id == knifeId then
			table.remove(profile.Data.Knives, i)
			DataService._modifyKnivesAfterEffects(player, profile.Data.Knives)
			return { successful = true, errorMessage = nil }
		end
	end
	return { successful = false, errorMessage = "Knife not found" }
end

function DataService._modifyGunsAfterEffects(player : Player, guns : { Types.GunSchema })
	debugPrint(DEBUG, `[DataService] _modifyGunsAfterEffects called for {player.Name}`)
end

function DataService.GetGunById(player : Player, gunId : string) : Types.GunSchema?
	local data = DataService.GetData(player)
	if not data then return nil end
	for _, gun in data.Guns do
		if gun.id == gunId then
			return gun
		end
	end
	return nil
end

function DataService.AddGun(player : Player, gunName : string) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] AddGun called for {player.Name} with name: {gunName}`)
	local profile = Profiles[player]
	if not profile then
		return { successful = false, errorMessage = "Profile not found" }
	end
	local gun : Types.GunSchema = {
		id = HttpService:GenerateGUID(false),
		name = gunName,
		equipped = false,
	}
	table.insert(profile.Data.Guns, gun)
	DataService._modifyGunsAfterEffects(player, profile.Data.Guns)
	return { successful = true, errorMessage = nil }
end

function DataService.RemoveGun(player : Player, gunId : string) : Types.OperationSuccessReturnValue
	debugPrint(DEBUG, `[DataService] RemoveGun called for {player.Name} with id: {gunId}`)
	local profile = Profiles[player]
	if not profile then
		return { successful = false, errorMessage = "Profile not found" }
	end
	for i, gun in profile.Data.Guns do
		if gun.id == gunId then
			table.remove(profile.Data.Guns, i)
			DataService._modifyGunsAfterEffects(player, profile.Data.Guns)
			return { successful = true, errorMessage = nil }
		end
	end
	return { successful = false, errorMessage = "Gun not found" }
end

return DataService