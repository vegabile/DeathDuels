local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapValidator = require(ReplicatedStorage.Map.MapValidator)

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

function TeleportDataValidator.validate(teleportData: any): (boolean, string?)
	if type(teleportData) ~= "table" then
		return false, "Teleport data is not a table"
	end

	local ok, err = validatePlayerList(teleportData.teamOnePlayers, "teamOnePlayers")
	if not ok then return false, err end

	ok, err = validatePlayerList(teleportData.teamTwoPlayers, "teamTwoPlayers")
	if not ok then return false, err end

	if type(teleportData.queueType) ~= "number" then
		return false, "queueType is not a number"
	end
	ok, err = MapValidator.validate(teleportData.mapName)
	if not ok then return false, err end
	if type(teleportData.loadouts) ~= "table" then
		return false, "loadouts is not a table"
	end
	if type(teleportData.timestamp) ~= "number" then
		return false, "timestamp is not a number"
	end

	return true, nil
end

return TeleportDataValidator
