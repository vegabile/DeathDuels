local Players = game:GetService("Players")
local KnifeController = require(script.Parent)
local InputRouter = require(script.Parent.Parent.InputRouter)

local localPlayer = Players.LocalPlayer

local function setupCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			KnifeController.onKnifeEquipped()
			InputRouter.bindWeapon("Knife", KnifeController.performAction)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			KnifeController.onKnifeUnequipped()
			InputRouter.unbindWeapon("Knife")
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		KnifeController.onPlayerDied()
		InputRouter.unbindWeapon("Knife")
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			KnifeController.onKnifeEquipped()
			InputRouter.bindWeapon("Knife", KnifeController.performAction)
			break
		end
	end
end

localPlayer.CharacterAdded:Connect(setupCharacter)

if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
