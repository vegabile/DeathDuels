local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ClientEventBus = require(script.Parent.Parent.ClientEventBus)
local KnifeController = require(script.Parent)

local localPlayer = Players.LocalPlayer

local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	KnifeController.onInputBegan(input, gameProcessed)
end)

ClientEventBus:Fire("RequestInputConnection", "KnifeInput", inputConnection)

localPlayer.CharacterAdded:Connect(function(character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			KnifeController.onKnifeEquipped()
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			KnifeController.onKnifeUnequipped()
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		KnifeController.onPlayerDied()
	end)
end)
