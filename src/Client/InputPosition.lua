local Players = game:GetService("Players")

local InputPosition = {}

function InputPosition.getInputPosition(): Vector3
	local player = Players.LocalPlayer
	print("[KNIFE] [InputPosition] getting input position")
	local mouse = player:GetMouse()
	local camera = workspace.CurrentCamera
	print(`[KNIFE] [InputPosition] mouse={mouse.X},{mouse.Y}`)

	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)

	if result then
		print(`[KNIFE] [InputPosition] raycast hit at {result.Position}`)
		return result.Position
	else
		local fallback = unitRay.Origin + unitRay.Direction * 1000
		print(`[KNIFE] [InputPosition] raycast miss fallback={fallback}`)
		return fallback
	end
end

return InputPosition
