local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KnifeController = require(script.Parent)
local InputRouter = require(script.Parent.Parent.InputRouter)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)

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

local function getOrCreateClientFolder(): Folder
	local folder = workspace:FindFirstChild("ClientKnifeProjectiles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientKnifeProjectiles"
		folder.Parent = workspace
	end
	return folder
end

NetworkRouter:Listen("KnifeThrowBroadcast", function(data)
	if type(data) ~= "table" then return end

	local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
	if not knifeModels then
		warn("[KnifeController] KnifeModels folder not found in ReplicatedStorage")
		return
	end

	local knifeModel = knifeModels:FindFirstChild(data.knifeName)
	if not knifeModel then
		warn("[KnifeController] Unknown knife model in broadcast: " .. tostring(data.knifeName))
		return
	end

	local folder = getOrCreateClientFolder()
	ProjectileFactory.spawnProjectile({
		template = knifeModel,
		directionVector = data.directionVector,
		spawnCFrame = data.spawnCFrame,
		parent = folder,
		transparency = 0,
	}, localPlayer, { folder }, nil)
end)
