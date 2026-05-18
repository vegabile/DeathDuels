local Players = game:GetService("Players")

local PowerController = require(script.Parent)
local Input = require(script.Parent.Input)



require(script.Parent.Effects.Reveal)
require(script.Parent.Effects.Blind)

PowerController.start()

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local abilityUi = playerGui:WaitForChild("AbilityUI", 10)
if not abilityUi then
	warn("[POWER] AbilityUI missing at PlayerGui.AbilityUI")
	return
end
if not abilityUi:IsA("ScreenGui") then
	warn(`[POWER] AbilityUI is {abilityUi.ClassName}; expected ScreenGui`)
	return
end

local frame = abilityUi:WaitForChild("Frame", 10)
if not frame then
	warn("[POWER] AbilityUI.Frame missing")
	return
end

local button = frame:WaitForChild("Button", 10)
if not button then
	warn("[POWER] AbilityUI.Frame.Button missing")
	return
end
if not button:IsA("TextButton") then
	warn(`[POWER] AbilityUI.Frame.Button is {button.ClassName}; expected TextButton`)
	return
end

Input.init(abilityUi, button)
