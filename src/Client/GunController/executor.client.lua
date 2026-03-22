local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ClientEventBus = require(script.Parent.Parent.ClientEventBus)
local GunController = require(script.Parent)

local localPlayer = Players.LocalPlayer

local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	GunController.onInputBegan(input, gameProcessed)
end)

ClientEventBus:Fire("RequestInputConnection", "GunInput", inputConnection)

local function setupCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunEquipped()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunUnequipped()
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		GunController.onPlayerDied()
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsGun") then
			GunController.onGunEquipped()
			break
		end
	end
end

localPlayer.CharacterAdded:Connect(setupCharacter)

if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
