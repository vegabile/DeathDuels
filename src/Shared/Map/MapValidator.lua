local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

	for _, map in mapsFolder:GetChildren() do
		if map.Name == mapName then
			return true, nil
		end
	end

	return false, `Unknown map: {mapName}`
end

return MapValidator
