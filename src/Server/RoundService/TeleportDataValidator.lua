local TeleportDataValidator = {}

function TeleportDataValidator.validate(teleportData: any): (boolean, string?)
	if type(teleportData) ~= "table" then
		return false, "Teleport data is not a table"
	end

	if type(teleportData.teamOnePlayers) ~= "table" then
		return false, "teamOnePlayers is not a table"
	end

	if type(teleportData.teamTwoPlayers) ~= "table" then
		return false, "teamTwoPlayers is not a table"
	end

	for i, userId in teleportData.teamOnePlayers do
		if type(userId) ~= "number" then
			return false, `teamOnePlayers[{i}] is not a number`
		end
	end

	for i, userId in teleportData.teamTwoPlayers do
		if type(userId) ~= "number" then
			return false, `teamTwoPlayers[{i}] is not a number`
		end
	end

	if #teleportData.teamOnePlayers == 0 then
		return false, "teamOnePlayers is empty"
	end

	if #teleportData.teamTwoPlayers == 0 then
		return false, "teamTwoPlayers is empty"
	end

	return true, nil
end

return TeleportDataValidator
