local GunUtility = {}

function GunUtility.findGunTool(character: Model): Tool?
	if not character then return nil end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			return child
		end
	end
	return nil
end

return GunUtility
