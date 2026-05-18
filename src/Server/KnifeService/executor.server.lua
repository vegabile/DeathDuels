local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local KnifeService = require(script.Parent)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)

NetworkRouter:CreateRemoteEvent("KnifeThrowBroadcast")

local function knifeTrace(message: string)
	if SharedConfigs.DEBUG_MODE then
		print(`[KnifeService.executor] {message}`)
	end
end

local handled = setmetatable({}, { __mode = "k" }) :: { [Player]: boolean }

local function setupPlayer(player)
	if handled[player] then
		warn(`[KnifeService.executor] setup skipped for {player.Name}: already handled`)
		return
	end
	handled[player] = true

	knifeTrace(`setupPlayer for {player.Name}`)
	KnifeService.OnPlayerAdded(player)

	player.CharacterAdded:Connect(function(character)
		knifeTrace(`CharacterAdded for {player.Name} => {character.Name}`)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			knifeTrace(`Humanoid died for {player.Name}`)
			KnifeService.OnPlayerDied(player)
		end)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	knifeTrace(`existing player setup {player.Name}`)
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	knifeTrace(`PlayerRemoving for {player.Name}`)
	KnifeService.OnPlayerRemoving(player)
end)
