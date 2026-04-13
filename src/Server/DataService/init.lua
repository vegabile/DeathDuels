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
local LeavingFlags = setmetatable({}, { __mode = "k" }) :: { [Player]: boolean }
local IntentionalEnds = setmetatable({}, { __mode = "k" }) :: { [Player]: boolean }

debugPrint(DEBUG, "[DataService] Module initialized, PlayerStore created")

local DataService = {}

local function profileFor(player: Player, op: string)
	local profile = Profiles[player]
	if not profile then
		warn(`[DataService.{op}] no profile for {player.Name}`)
		return nil
	end
	return profile
end

function DataService:GetCoin(player: Player): number?
	local profile = profileFor(player, "GetCoin")
	if not profile then return nil end
	return profile.Data.Coin
end

function DataService:AddCoin(player: Player, amount: number)
	local profile = profileFor(player, "AddCoin")
	if not profile then return end
	profile.Data.Coin += amount
end

function DataService:GetKnives(player: Player): { [string]: boolean }?
	local profile = profileFor(player, "GetKnives")
	if not profile then return nil end
	local copy = {}
	for name, owned in profile.Data.Knives do
		copy[name] = owned
	end
	return copy
end

function DataService:HasKnife(player: Player, knifeName: string): boolean
	local profile = profileFor(player, "HasKnife")
	if not profile then return false end
	return profile.Data.Knives[knifeName] == true
end

function DataService:AddKnife(player: Player, knifeName: string)
	local profile = profileFor(player, "AddKnife")
	if not profile then return end
	profile.Data.Knives[knifeName] = true
end

function DataService:RemoveKnife(player: Player, knifeName: string)
	local profile = profileFor(player, "RemoveKnife")
	if not profile then return end
	profile.Data.Knives[knifeName] = nil
end

function DataService:GetGuns(player: Player): { [string]: boolean }?
	local profile = profileFor(player, "GetGuns")
	if not profile then return nil end
	local copy = {}
	for name, owned in profile.Data.Guns do
		copy[name] = owned
	end
	return copy
end

function DataService:HasGun(player: Player, gunName: string): boolean
	local profile = profileFor(player, "HasGun")
	if not profile then return false end
	return profile.Data.Guns[gunName] == true
end

function DataService:AddGun(player: Player, gunName: string)
	local profile = profileFor(player, "AddGun")
	if not profile then return end
	profile.Data.Guns[gunName] = true
end

function DataService:RemoveGun(player: Player, gunName: string)
	local profile = profileFor(player, "RemoveGun")
	if not profile then return end
	profile.Data.Guns[gunName] = nil
end

function DataService:OnPlayerAdded(player: Player)
	debugPrint(DEBUG, `[DataService] OnPlayerAdded starting for {player.Name} ({player.UserId})`)

	if Profiles[player] ~= nil then
		warn(`[DataService] OnPlayerAdded skipped for {player.Name}: profile already loaded`)
		return
	end

	local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return LeavingFlags[player] == true
		end,
	})

	if profile == nil then
		if LeavingFlags[player] then
			debugPrint(DEBUG, `[DataService] Profile load cancelled for {player.Name} (player left during load)`)
			return
		end
		warn(`[DataService] Failed to load profile for {player.Name}, kicking`)
		player:Kick("Unable to load your data. Please rejoin.")
		return
	end

	debugPrint(DEBUG, `[DataService] Profile loaded for {player.Name}`)

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	debugPrint(DEBUG, `[DataService] Reconciled profile for {player.Name}`)

	profile.OnSessionEnd:Connect(function()
		debugPrint(DEBUG, `[DataService] Session ended for {player.Name}`)
		Profiles[player] = nil
		if IntentionalEnds[player] then
			IntentionalEnds[player] = nil
			return
		end
		warn(`[DataService] Session externally ended for {player.Name} (stolen or evicted)`)
		player:Kick("Your data session ended. Please rejoin.")
	end)

	if player:IsDescendantOf(Players) and not LeavingFlags[player] then
		Profiles[player] = profile
		debugPrint(DEBUG, `[DataService] Profile stored for {player.Name}`)
	else
		debugPrint(DEBUG, `[DataService] {player.Name} left before profile loaded, ending session`)
		IntentionalEnds[player] = true
		profile:EndSession()
	end
end

function DataService:OnPlayerRemoving(player: Player)
	debugPrint(DEBUG, `[DataService] OnPlayerRemoving for {player.Name}`)
	LeavingFlags[player] = true
	local profile = Profiles[player]
	if profile then
		debugPrint(DEBUG, `[DataService] Ending session for {player.Name}`)
		IntentionalEnds[player] = true
		profile:EndSession()
	end
end

return DataService
