


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponDistributor = require(script.Parent)

local function validateWeapons(): (boolean, { string }?, { Tool }?, { Tool }?)
	local problems = {}
	local knives = {}
	local guns = {}

	local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
	if not knifeModels then
		table.insert(problems, "ReplicatedStorage.KnifeModels missing")
	else
		for _, child in knifeModels:GetChildren() do
			if child:IsA("Tool") then
				table.insert(knives, child)
			else
				table.insert(
					problems,
					`KnifeModels.{child.Name} is not a Tool (got {child.ClassName})`
				)
			end
		end
		if #knives == 0 then
			table.insert(problems, "KnifeModels contains zero Tools")
		end
	end

	local gunModels = ReplicatedStorage:FindFirstChild("GunModels")
	if not gunModels then
		table.insert(problems, "ReplicatedStorage.GunModels missing")
	else
		for _, child in gunModels:GetChildren() do
			if child:IsA("Tool") then
				table.insert(guns, child)
			else
				table.insert(
					problems,
					`GunModels.{child.Name} is not a Tool (got {child.ClassName})`
				)
			end
		end
		if #guns == 0 then
			table.insert(problems, "GunModels contains zero Tools")
		end
	end

	if #problems > 0 then
		return false, problems, nil, nil
	end
	return true, nil, knives, guns
end

local validationOk, problems, knives, guns = validateWeapons()
if not validationOk then
	warn("[WeaponDistributor] CRITICAL — weapon validation failed:")
	for _, msg in problems do
		warn(`  - {msg}`)
	end
	error("[WeaponDistributor] cannot initialize — see warnings above")
end

local initOk = WeaponDistributor.init(knives, guns)
if not initOk then
	error("[WeaponDistributor] init failed")
end
