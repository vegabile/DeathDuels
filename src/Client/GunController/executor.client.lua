local Players = game:GetService("Players")
local GunController = require(script.Parent)
local InputRouter = require(script.Parent.Parent.InputRouter)

local localPlayer = Players.LocalPlayer

local function setupCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunEquipped()
			InputRouter.bindWeapon("Gun", GunController.performAction)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunUnequipped()
			InputRouter.unbindWeapon("Gun")
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		GunController.onPlayerDied()
		InputRouter.unbindWeapon("Gun")
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunEquipped()
			InputRouter.bindWeapon("Gun", GunController.performAction)
			break
		end
	end
end

localPlayer.CharacterAdded:Connect(setupCharacter)

if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
