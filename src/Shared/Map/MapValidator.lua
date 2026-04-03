local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

local MapValidator = {}

function MapValidator.validate(mapName: any): (boolean, string?)
	if type(mapName) ~= "string" then
		return false, "mapName is not a string"
	end

	local mapsFolder = ReplicatedStorage:FindFirstChild("Maps")
	if not mapsFolder then
		warn("MapValidator: Maps folder not found in ReplicatedStorage")
		return false, "Maps folder not found"
	end

	local mapModel = nil
	for _, map in mapsFolder:GetChildren() do
		if map.Name == mapName then
			mapModel = map
			break
		end
	end

	if not mapModel then
		return false, `Unknown map: {mapName}`
	end

	local redCount = 0
	local blueCount = 0
	for _, desc in mapModel:GetDescendants() do
		if desc.Name == Configs.SPAWN_PARTS.Red then
			redCount += 1
		elseif desc.Name == Configs.SPAWN_PARTS.Blue then
			blueCount += 1
		end
	end

	if redCount < Configs.MAX_PLAYERS_PER_TEAM or blueCount < Configs.MAX_PLAYERS_PER_TEAM then
		error(`Map "{mapName}" has insufficient spawn parts: {redCount} red, {blueCount} blue, need {Configs.MAX_PLAYERS_PER_TEAM} each`)
	end

	return true, nil
end

return MapValidator
