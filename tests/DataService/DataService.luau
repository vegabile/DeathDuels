--// Lune-compatible copy of src/Server/DataService/init.lua
--// Uses dependency injection instead of Roblox requires for testability

local DataService = {}

function DataService.new(deps)
	local self = {}

	local Profiles = {}
	local debugPrint = deps.debugPrint
	local DEBUG = deps.debugMode
	local PlayerStore = deps.playerStore
	local generateGUID = deps.generateGUID
	local isPlayerInGame = deps.isPlayerInGame
	local kickPlayer = deps.kickPlayer

	function self.GetProfile(player)
		debugPrint(DEBUG, `[DataService] GetProfile called for {player.Name}`)
		return Profiles[player]
	end

	function self.GetData(player)
		debugPrint(DEBUG, `[DataService] GetData called for {player.Name}`)
		local profile = Profiles[player]
		if profile then
			return profile.Data
		end
		debugPrint(DEBUG, `[DataService] No profile found for {player.Name}`)
		return nil
	end

	function self.OnPlayerAdded(player)
		debugPrint(DEBUG, `[DataService] OnPlayerAdded starting for {player.Name} ({player.UserId})`)

		local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`)

		if profile == nil then
			debugPrint(DEBUG, `[DataService] Failed to load profile for {player.Name}, kicking`)
			kickPlayer(player, "Unable to load your data. Please rejoin.")
			return
		end

		debugPrint(DEBUG, `[DataService] Profile loaded for {player.Name}`)

		profile:AddUserId(player.UserId)
		profile:Reconcile()

		debugPrint(DEBUG, `[DataService] Reconciled profile for {player.Name}`)

		profile.OnSessionEnd:Connect(function()
			debugPrint(DEBUG, `[DataService] Session ended for {player.Name}, clearing profile`)
			Profiles[player] = nil
			kickPlayer(player, "Your data session ended. Please rejoin.")
		end)

		if isPlayerInGame(player) then
			Profiles[player] = profile
			debugPrint(DEBUG, `[DataService] Profile stored for {player.Name}`)
		else
			debugPrint(DEBUG, `[DataService] {player.Name} left before profile loaded, ending session`)
			profile:EndSession()
		end
	end

	function self.OnPlayerRemoving(player)
		debugPrint(DEBUG, `[DataService] OnPlayerRemoving for {player.Name}`)
		local profile = Profiles[player]
		if profile then
			debugPrint(DEBUG, `[DataService] Ending session for {player.Name}`)
			profile:EndSession()
		end
	end

	function self._modifyCoinsAfterEffects(player, newCoinAmount)
		debugPrint(DEBUG, `[DataService] _modifyCoinsAfterEffects called for {player.Name} with newCoinAmount: {newCoinAmount}`)
	end

	function self._modifyCoins(player, newCoinAmount)
		debugPrint(DEBUG, `[DataService] _modifyCoins called for {player.Name} with newCoinAmount: {newCoinAmount}`)
		local profile = Profiles[player]
		if profile then
			profile.Data.Coin = newCoinAmount
			debugPrint(DEBUG, `[DataService] Coin amount updated for {player.Name} to {newCoinAmount}`)
			self._modifyCoinsAfterEffects(player, newCoinAmount)
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

	function self.AddCoins(player, amount)
		debugPrint(DEBUG, `[DataService] AddCoins called for {player.Name} with amount: {amount}`)
		local data = self.GetData(player)
		if not data then
			return { successful = false, errorMessage = "Profile not found" }
		end
		return self._modifyCoins(player, data.Coin + amount)
	end

	function self.RemoveCoins(player, amount)
		debugPrint(DEBUG, `[DataService] RemoveCoins called for {player.Name} with amount: {amount}`)
		local data = self.GetData(player)
		if not data then
			return { successful = false, errorMessage = "Profile not found" }
		end
		return self._modifyCoins(player, data.Coin - amount)
	end

	function self._modifyKnivesAfterEffects(player, knives)
		debugPrint(DEBUG, `[DataService] _modifyKnivesAfterEffects called for {player.Name}`)
	end

	function self.GetKnifeById(player, knifeId)
		local data = self.GetData(player)
		if not data then return nil end
		for _, knife in data.Knives do
			if knife.id == knifeId then
				return knife
			end
		end
		return nil
	end

	function self.AddKnife(player, knifeName)
		debugPrint(DEBUG, `[DataService] AddKnife called for {player.Name} with name: {knifeName}`)
		local profile = Profiles[player]
		if not profile then
			return { successful = false, errorMessage = "Profile not found" }
		end
		local knife = {
			id = generateGUID(),
			name = knifeName,
			equipped = false,
		}
		table.insert(profile.Data.Knives, knife)
		self._modifyKnivesAfterEffects(player, profile.Data.Knives)
		return { successful = true, errorMessage = nil }
	end

	function self.RemoveKnife(player, knifeId)
		debugPrint(DEBUG, `[DataService] RemoveKnife called for {player.Name} with id: {knifeId}`)
		local profile = Profiles[player]
		if not profile then
			return { successful = false, errorMessage = "Profile not found" }
		end
		for i, knife in profile.Data.Knives do
			if knife.id == knifeId then
				table.remove(profile.Data.Knives, i)
				self._modifyKnivesAfterEffects(player, profile.Data.Knives)
				return { successful = true, errorMessage = nil }
			end
		end
		return { successful = false, errorMessage = "Knife not found" }
	end

	function self._modifyGunsAfterEffects(player, guns)
		debugPrint(DEBUG, `[DataService] _modifyGunsAfterEffects called for {player.Name}`)
	end

	function self.GetGunById(player, gunId)
		local data = self.GetData(player)
		if not data then return nil end
		for _, gun in data.Guns do
			if gun.id == gunId then
				return gun
			end
		end
		return nil
	end

	function self.AddGun(player, gunName)
		debugPrint(DEBUG, `[DataService] AddGun called for {player.Name} with name: {gunName}`)
		local profile = Profiles[player]
		if not profile then
			return { successful = false, errorMessage = "Profile not found" }
		end
		local gun = {
			id = generateGUID(),
			name = gunName,
			equipped = false,
		}
		table.insert(profile.Data.Guns, gun)
		self._modifyGunsAfterEffects(player, profile.Data.Guns)
		return { successful = true, errorMessage = nil }
	end

	function self.RemoveGun(player, gunId)
		debugPrint(DEBUG, `[DataService] RemoveGun called for {player.Name} with id: {gunId}`)
		local profile = Profiles[player]
		if not profile then
			return { successful = false, errorMessage = "Profile not found" }
		end
		for i, gun in profile.Data.Guns do
			if gun.id == gunId then
				table.remove(profile.Data.Guns, i)
				self._modifyGunsAfterEffects(player, profile.Data.Guns)
				return { successful = true, errorMessage = nil }
			end
		end
		return { successful = false, errorMessage = "Gun not found" }
	end

	return self
end

return DataService
