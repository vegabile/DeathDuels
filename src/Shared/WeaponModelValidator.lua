local WeaponModelValidator = {}

function WeaponModelValidator.validateKnife(tool: any): (boolean, string?)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return false, "knife template must be a Tool instance"
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return false, "knife template missing Handle"
	end
	if not handle:IsA("BasePart") then
		return false, "knife Handle must be a BasePart"
	end

	return true, nil
end

function WeaponModelValidator.validateGun(tool: any): (boolean, string?)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return false, "gun template must be a Tool instance"
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return false, "gun template missing Handle"
	end
	if not handle:IsA("BasePart") then
		return false, "gun Handle must be a BasePart"
	end

	return true, nil
end

return WeaponModelValidator
