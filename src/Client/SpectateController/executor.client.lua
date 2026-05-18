



local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local SpectateController = require(script.Parent)
local Configs = require(script.Parent.Configs)
local ClientEventBus = require(script.Parent.Parent.ClientEventBus)

local camera = Workspace.CurrentCamera
if not camera then
	warn("[Spectate] Workspace.CurrentCamera missing at bootstrap; spectate camera will be nil")
end

SpectateController.Init(camera, Players.LocalPlayer)

ClientEventBus:Connect("RoundUpdate", function(snapshot)
	SpectateController.HandleRoundUpdate(snapshot)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == Configs.INPUT_NEXT_TARGET then
		SpectateController.SelectNext()
	elseif input.KeyCode == Configs.INPUT_PREVIOUS_TARGET then
		SpectateController.SelectPrevious()
	elseif input.KeyCode == Configs.INPUT_CLEAR_TARGET then
		SpectateController.Clear()
	end
end)
