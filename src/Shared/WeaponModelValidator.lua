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
	local hitbox = tool:FindFirstChild("Hitbox")
	if hitbox and not hitbox:IsA("BasePart") then
		return false, "knife Hitbox must be a BasePart when present"
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
	local shootPoint = handle:FindFirstChild("ShootPoint")
	if shootPoint and not shootPoint:IsA("Attachment") then
		return false, "gun ShootPoint must be an Attachment when present"
	end
	local shootAttachment = handle:FindFirstChild("ShootAttachment")
	if shootAttachment and not shootAttachment:IsA("Attachment") then
		return false, "gun ShootAttachment must be an Attachment when present"
	end

	return true, nil
end

return WeaponModelValidator
