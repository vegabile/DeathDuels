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
		Power = Configs.DEFAULT_LOADOUT.Power,
		powerName = Configs.DEFAULT_LOADOUT.Power,
	}
end




local function cloneTeamList(list)
	local out = {}
	for i, entry in list do out[i] = entry end
	return out
end

local function buildRosterSet(teamOnePlayers, teamTwoPlayers)
	local roster = {}
	for _, entry in teamOnePlayers do roster[entry.UserId] = true end
	for _, entry in teamTwoPlayers do roster[entry.UserId] = true end
	return roster
end

local function sanitizeParties(parties, roster)
	if parties == nil then
		return true, nil, {}
	end
	if type(parties) ~= "table" then
		return false, "parties is not a table", nil
	end

	local sanitized = {}
	for partyId, entry in parties do
		if type(partyId) ~= "string" then
			return false, "parties key is not a string", nil
		end
		if type(entry) ~= "table" then
			return false, `parties[{partyId}] is not a table`, nil
		end
		if type(entry.leaderUserId) ~= "number" then
			return false, `parties[{partyId}].leaderUserId is not a number`, nil
		end
		if not roster[entry.leaderUserId] then
			return false, `parties[{partyId}].leaderUserId is not in the roster`, nil
		end
		if type(entry.memberUserIds) ~= "table" then
			return false, `parties[{partyId}].memberUserIds is not a table`, nil
		end

		local memberUserIds = {}
		for i, userId in entry.memberUserIds do
			if type(userId) ~= "number" then
				return false, `parties[{partyId}].memberUserIds[{i}] is not a number`, nil
			end
			if not roster[userId] then
				return false, `parties[{partyId}].memberUserIds[{i}] is not in the roster`, nil
			end
			table.insert(memberUserIds, userId)
		end

		sanitized[partyId] = {
			leaderUserId = entry.leaderUserId,
			memberUserIds = memberUserIds,
		}
	end

	return true, nil, sanitized
end

local function fillLoadouts(sanitized)
	if type(sanitized.loadouts) ~= "table" then
		if sanitized.loadouts ~= nil then
			warn(`[TeleportDataValidator] loadouts is {typeof(sanitized.loadouts)} — defaulting`)
		end
		sanitized.loadouts = {}
	else
		
		local copy = {}
		for k, v in sanitized.loadouts do
			local powerName = v.Power or v.powerName
			copy[k] = {
				knifeName = v.knifeName,
				gunName = v.gunName,
				Power = powerName,
				powerName = powerName,
			}
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
		if loadout.Power == nil or loadout.Power == "" then
			loadout.Power = Configs.DEFAULT_LOADOUT.Power
		end
		if loadout.powerName == nil or loadout.powerName == "" then
			loadout.powerName = loadout.Power
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
	if type(teleportData.matchId) ~= "string" or teleportData.matchId == "" then
		return false, "matchId is missing or not a string", nil
	end
	if type(teleportData.placeId) ~= "number" or teleportData.placeId <= 0 then
		return false, "placeId is missing or not a positive number", nil
	end
	if type(teleportData.reservedServerAccessCode) ~= "string" or teleportData.reservedServerAccessCode == "" then
		return false, "reservedServerAccessCode is missing or not a string", nil
	end

	local roster = buildRosterSet(teleportData.teamOnePlayers, teleportData.teamTwoPlayers)
	local partiesOk, partiesErr, parties = sanitizeParties(teleportData.parties, roster)
	if not partiesOk then return false, partiesErr, nil end

	local sanitized = {
		teamOnePlayers = cloneTeamList(teleportData.teamOnePlayers),
		teamTwoPlayers = cloneTeamList(teleportData.teamTwoPlayers),
		queueType = teleportData.queueType,
		mapName = teleportData.mapName,
		timestamp = teleportData.timestamp,
		loadouts = teleportData.loadouts,
		parties = parties,
		matchId = teleportData.matchId,
		placeId = teleportData.placeId,
		reservedServerAccessCode = teleportData.reservedServerAccessCode,
	}
	fillLoadouts(sanitized)

	return true, nil, sanitized
end

return TeleportDataValidator
