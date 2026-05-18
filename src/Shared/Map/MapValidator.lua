local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local MapConfigs = require(ReplicatedStorage.Map.Configs)

local MapValidator = {}

function MapValidator.validate(mapName: any, queueType: number?): (boolean, string?)
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

	local isRegistered = false
	for _, registeredName in MapConfigs.REGISTERED_MAPS do
		if registeredName == mapName then
			isRegistered = true
			break
		end
	end
	if not isRegistered then
		warn(`[MapValidator] Map "{mapName}" is not in REGISTERED_MAPS`)
		return false, `Map "{mapName}" is not registered`
	end

	if not mapModel:IsA("Model") then
		warn(`[MapValidator] Map "{mapName}" exists but is not a Model instance`)
		return false, `Map "{mapName}" is not a Model`
	end

	local redCount = 0
	local blueCount = 0
	for _, desc in mapModel:GetDescendants() do
		if desc.Name == Configs.SPAWN_PARTS.Red and desc:IsA("BasePart") then
			redCount += 1
		elseif desc.Name == Configs.SPAWN_PARTS.Blue and desc:IsA("BasePart") then
			blueCount += 1
		end
	end

	local requiredPerTeam = Configs.MAX_PLAYERS_PER_TEAM
	if type(queueType) == "number" and Configs.GAME_MODES[queueType] then
		requiredPerTeam = Configs.GAME_MODES[queueType].playersPerTeam
	end

	if redCount < requiredPerTeam or blueCount < requiredPerTeam then
		warn(`[MapValidator] Map "{mapName}" has insufficient spawn parts: {redCount} red, {blueCount} blue (need {requiredPerTeam} each)`)
		return false, `Map "{mapName}" has insufficient spawn parts`
	end

	return true, nil
end

return MapValidator
