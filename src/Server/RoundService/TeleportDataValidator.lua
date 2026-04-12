local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapValidator = require(ReplicatedStorage.Map.MapValidator)
local Configs = require(ReplicatedStorage.Round.Configs)

local TeleportDataValidator = {}

local function validatePlayerList(list: any, fieldName: string): (boolean, string?)
	if type(list) ~= "table" then
		return false, `{fieldName} is not a table`
	end
	if #list == 0 then
		return false, `{fieldName} is empty`
	end
	for i, entry in list do
		if type(entry) ~= "table" then
			return false, `{fieldName}[{i}] is not a table`
		end
		if type(entry.UserId) ~= "number" then
			return false, `{fieldName}[{i}].UserId is not a number`
		end
		if type(entry.Name) ~= "string" then
			return false, `{fieldName}[{i}].Name is not a string`
		end
	end
	return true, nil
end

local function cloneDefaultLoadout()
	return {
		knifeName = Configs.DEFAULT_LOADOUT.knifeName,
		gunName = Configs.DEFAULT_LOADOUT.gunName,
	}
end

--// Shallow copy teams so the sanitized table can be mutated without touching
--// the caller's data. Entries themselves are kept by reference — the fields
--// we read (UserId, Name) are immutable per-entry.
local function cloneTeamList(list)
	local out = {}
	for i, entry in list do out[i] = entry end
	return out
end

local function fillLoadouts(sanitized)
	if type(sanitized.loadouts) ~= "table" then
		if sanitized.loadouts ~= nil then
			warn(`[TeleportDataValidator] loadouts is {typeof(sanitized.loadouts)} — defaulting`)
		end
		sanitized.loadouts = {}
	else
		--// Copy so we don't mutate the caller's loadouts table.
		local copy = {}
		for k, v in sanitized.loadouts do
			copy[k] = { knifeName = v.knifeName, gunName = v.gunName }
		end
		sanitized.loadouts = copy
	end

	local function fillFor(entry)
		local key = tostring(entry.UserId)
		local loadout = sanitized.loadouts[key]
		if not loadout then
			sanitized.loadouts[key] = cloneDefaultLoadout()
			return
		end
		if loadout.knifeName == nil then
			loadout.knifeName = Configs.DEFAULT_LOADOUT.knifeName
		end
		if loadout.gunName == nil then
			loadout.gunName = Configs.DEFAULT_LOADOUT.gunName
		end
	end
	for _, entry in sanitized.teamOnePlayers do fillFor(entry) end
	for _, entry in sanitized.teamTwoPlayers do fillFor(entry) end
end

function TeleportDataValidator.validate(teleportData: any): (boolean, string?, { [string]: any }?)
	if type(teleportData) ~= "table" then
		return false, "Teleport data is not a table", nil
	end

	local ok, err = validatePlayerList(teleportData.teamOnePlayers, "teamOnePlayers")
	if not ok then return false, err, nil end

	ok, err = validatePlayerList(teleportData.teamTwoPlayers, "teamTwoPlayers")
	if not ok then return false, err, nil end

	if type(teleportData.queueType) ~= "number" then
		return false, "queueType is not a number", nil
	end
	ok, err = MapValidator.validate(teleportData.mapName)
	if not ok then return false, err, nil end
	if type(teleportData.timestamp) ~= "number" then
		return false, "timestamp is not a number", nil
	end

	local sanitized = {
		teamOnePlayers = cloneTeamList(teleportData.teamOnePlayers),
		teamTwoPlayers = cloneTeamList(teleportData.teamTwoPlayers),
		queueType = teleportData.queueType,
		mapName = teleportData.mapName,
		timestamp = teleportData.timestamp,
		loadouts = teleportData.loadouts,
	}
	fillLoadouts(sanitized)

	return true, nil, sanitized
end

return TeleportDataValidator
