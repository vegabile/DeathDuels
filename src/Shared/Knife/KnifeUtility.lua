local KnifeUtility = {}

function KnifeUtility.findKnifeTool(character: Model): Tool?
	if not character then
		print("[KNIFE] [KnifeUtility] findKnifeTool no character")
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			print("[KNIFE] [KnifeUtility] found knife tool " .. child.Name)
			return child
		end
	end
	print("[KNIFE] [KnifeUtility] knife tool not found")
	return nil
end

return KnifeUtility
