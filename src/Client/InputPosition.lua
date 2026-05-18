local Players = game:GetService("Players")

local InputPosition = {}

function InputPosition.getInputPosition(): Vector3
	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local camera = workspace.CurrentCamera
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)

	if result then
		return result.Position
	else
		local fallback = unitRay.Origin + unitRay.Direction * 1000
		return fallback
	end
end

return InputPosition
