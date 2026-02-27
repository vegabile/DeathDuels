local Types = require(script.Types)
type DataSchema = Types.DataSchema

local Players = game:GetService("Players")
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

function DataService:GetProfile(player: Player)
	debugPrint(DEBUG, `[DataService] GetProfile called for {player.Name}`)
	return Profiles[player]
end

function DataService:GetData(player: Player): DataSchema?
	debugPrint(DEBUG, `[DataService] GetData called for {player.Name}`)
	local profile = Profiles[player]
	if profile then
		return profile.Data
	end
	debugPrint(DEBUG, `[DataService] No profile found for {player.Name}`)
	return nil
end

function DataService:OnPlayerAdded(player: Player)
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

function DataService:OnPlayerRemoving(player: Player)
	debugPrint(DEBUG, `[DataService] OnPlayerRemoving for {player.Name}`)
	local profile = Profiles[player]
	if profile then
		debugPrint(DEBUG, `[DataService] Ending session for {player.Name}`)
		profile:EndSession()
	end
end

return DataService