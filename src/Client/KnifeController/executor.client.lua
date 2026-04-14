local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KnifeController = require(script.Parent)
local InputRouter = require(script.Parent.Parent.InputRouter)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local ProjectileFactory = require(ReplicatedStorage.Knife.ProjectileFactory)

local localPlayer = Players.LocalPlayer
local function knifeTrace(message: string)
	print("[KNIFE] " .. message)
end

local function setupCharacter(character)
	knifeTrace(`setupCharacter begin for {character.Name}`)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			knifeTrace(`Knife tool added: {child.Name}`)
			KnifeController.onKnifeEquipped()
			InputRouter.bindWeapon("Knife", KnifeController.performAction)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			knifeTrace(`Knife tool removed: {child.Name}`)
			KnifeController.onKnifeUnequipped()
			InputRouter.unbindWeapon("Knife")
		end
	end)

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		knifeTrace(`Character died in KnifeController client: {character.Name}`)
		KnifeController.onPlayerDied()
		InputRouter.unbindWeapon("Knife")
	end)

	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("IsKnife") then
			knifeTrace(`setupCharacter found existing knife: {child.Name}`)
			KnifeController.onKnifeEquipped()
			InputRouter.bindWeapon("Knife", KnifeController.performAction)
			break
		end
	end
end

localPlayer.CharacterAdded:Connect(setupCharacter)

if localPlayer.Character then
	knifeTrace(`initial setup for existing character {localPlayer.Character.Name}`)
	setupCharacter(localPlayer.Character)
end

local function getOrCreateClientFolder(): Folder
	local folder = workspace:FindFirstChild("ClientKnifeProjectiles")
	if not folder then
		knifeTrace("ClientKnifeProjectiles folder missing; creating")
		folder = Instance.new("Folder")
		folder.Name = "ClientKnifeProjectiles"
		folder.Parent = workspace
	end
	return folder
end

NetworkRouter:Listen("KnifeThrowBroadcast", function(data)
	knifeTrace(`received KnifeThrowBroadcast type={type(data)}`)
	if type(data) ~= "table" then
		warn("[KNIFE] [KnifeController] Invalid KnifeThrowBroadcast payload type")
		return
	end
	if typeof(data.spawnCFrame) ~= "CFrame" or typeof(data.directionVector) ~= "Vector3" or type(data.throwerUserId) ~= "number" or type(data.knifeName) ~= "string" then
		warn("[KNIFE] [KnifeController] Invalid KnifeThrowBroadcast payload")
		return
	end

	local thrower = Players:GetPlayerByUserId(data.throwerUserId)
	if not thrower then
		warn("[KNIFE] [KnifeController] Unknown thrower in KnifeThrowBroadcast: " .. tostring(data.throwerUserId))
		return
	end
	knifeTrace(`broadcast received from {thrower.Name} ({data.throwerUserId}) knife={data.knifeName}`)

	local folder = getOrCreateClientFolder()
	knifeTrace("using ClientKnifeProjectiles folder")
	local blacklist = { folder }
	local ignoreFolder = workspace:FindFirstChild("KnifeIgnoreFolder")
	if ignoreFolder then
		knifeTrace("excluding workspace.KnifeIgnoreFolder from collision checks")
		table.insert(blacklist, ignoreFolder)
	end
	if thrower and thrower.Character then
		knifeTrace(`adding thrower character blacklist: {thrower.Name}`)
		table.insert(blacklist, thrower.Character)
	end

	local knifeModels = ReplicatedStorage:FindFirstChild("KnifeModels")
	if not knifeModels then
		warn("[KNIFE] [KnifeController] KnifeModels folder not found in ReplicatedStorage")
		return
	end

	local knifeModel = knifeModels:FindFirstChild(data.knifeName)
	if not knifeModel then
		warn("[KNIFE] [KnifeController] Unknown knife model in broadcast: " .. tostring(data.knifeName))
		return
	end
	knifeTrace(`resolved knifeModel for broadcast: {knifeModel.Name}`)

	ProjectileFactory.spawnProjectile({
		template = knifeModel,
		directionVector = data.directionVector,
		spawnCFrame = data.spawnCFrame,
		parent = folder,
		transparency = 0,
	}, thrower, blacklist, nil)
	knifeTrace("spawned cosmetic projectile from broadcast")
end)
