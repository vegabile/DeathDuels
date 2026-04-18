local Players = game:GetService("Players")

local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilityUi = playerGui:WaitForChild("AbilityUI")
if not abilityUi:IsA("ScreenGui") then
	warn(`[POWER] AbilityUI is {abilityUi.ClassName}, expected ScreenGui`)
	return
end

local frame = abilityUi:WaitForChild("Frame")
local button = frame:WaitForChild("Button")
if not button:IsA("TextButton") then
	warn(`[POWER] AbilityUI.Frame.Button is {button.ClassName}, expected TextButton`)
	return
end

Input.init(abilityUi, button)
