local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)
local SharedConfigs = require(ReplicatedStorage.Knife.Configs)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)

local ServerConfigs = require(script.Parent.Parent.Configs)
local TeleportMetadataService = require(script.Parent.Parent.Parent.RoundService.TeleportMetadataService)
local DEBUG = ServerConfigs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local StabAction = {}

StabAction.name = "Stab"
StabAction.cooldown = SharedConfigs.StabCooldown
StabAction.duration = SharedConfigs.StabDuration

do
	local AnimationType = require(ReplicatedStorage.Animations.AnimationType)
	local AnimationProfile = require(ReplicatedStorage.Animations.AnimationProfile)
	local profile = AnimationProfile.resolve("Knife", SharedConfigs.AnimationProfiles, AnimationType.Stab)
	StabAction.animationId = (profile and profile.id) or ""
end

local function processHitPlayer(attacker: Player, playerState: any, hitPlayer: Player?, hitCharacter: Model?)
	if not hitPlayer or not hitCharacter then return end
	if hitPlayer == attacker then return end
	if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(attacker) then return end
	if playerState.alreadyHit[hitPlayer] then return end

	local attackerChar = attacker.Character
	local attackerRoot = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local victimRoot = hitCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if attackerRoot and victimRoot and (attackerRoot.Position - victimRoot.Position).Magnitude > SharedConfigs.MAX_STAB_DISTANCE then
		return
	end

	playerState.alreadyHit[hitPlayer] = true
	local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute("LastDamageSource", attacker.UserId)
		humanoid.Health = 0
	end
	debugPrint(DEBUG, `[StabAction] {attacker.Name} killed {hitPlayer.Name}`)
end

function StabAction.serverExecute(player: Player, playerState: any, _directionVector: Vector3?)
	playerState.alreadyHit = {}
	local startTime = tick()

	local character = player.Character
	if not character then
		warn(`[KNIFE] [StabAction] no character for {player.Name}`)
		return
	end
	local knifeTool = KnifeUtility.findKnifeTool(character)
	if not knifeTool then
		warn(`[KNIFE] [StabAction] no knife tool for {player.Name}`)
		return
	end
	local hitbox = knifeTool:FindFirstChild("Hitbox") :: BasePart?
	if not hitbox then
		warn(`[KNIFE] [StabAction] no Hitbox on knife for {player.Name}`)
		return
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	
	local heartbeatConn: RBXScriptConnection? = nil

	local function tearDown()
		if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
		if playerState.stabTouchedConn then
			playerState.stabTouchedConn:Disconnect()
			playerState.stabTouchedConn = nil
		end
		playerState.alreadyHit = {}
		playerState.currentTickConnection = nil
	end

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if tick() - startTime >= SharedConfigs.StabHitWindow then
			tearDown()
			return
		end

		local currentChar = player.Character
		if not currentChar then return end
		local currentTool = KnifeUtility.findKnifeTool(currentChar)
		if not currentTool then return end
		local currentHitbox = currentTool:FindFirstChild("Hitbox") :: BasePart?
		if not currentHitbox then return end

		local parts = workspace:GetPartsInPart(currentHitbox, overlapParams)
		for _, part in parts do
			local hitCharacter = part:FindFirstAncestorOfClass("Model")
			if not hitCharacter then continue end

			local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			if not hitPlayer then continue end
			if hitPlayer == player then continue end
			if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then continue end
			if playerState.alreadyHit[hitPlayer] then continue end

			if attackerRoot then
				local victimRoot = hitCharacter:FindFirstChild("HumanoidRootPart")
				if victimRoot and (attackerRoot.Position - victimRoot.Position).Magnitude > SharedConfigs.MAX_STAB_DISTANCE then
					continue
				end
			end

			playerState.alreadyHit[hitPlayer] = true
			local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if hitPlayer:GetAttribute("ShieldActive") then
					hitPlayer:SetAttribute("ShieldActive", nil)
					debugPrint(DEBUG, `[StabAction] ShieldActive absorbed stab on {hitPlayer.Name}`)
				else
					humanoid:SetAttribute("LastDamageSource", player.UserId)
					humanoid:TakeDamage(SharedConfigs.StabDamage)
					debugPrint(DEBUG, `[StabAction] {player.Name} stabbed {hitPlayer.Name}`)
				end
			end
		end
	end)
	
	playerState.currentTickConnection = heartbeatConn

	
	playerState.stabTouchedConn = hitbox.Touched:Connect(function(part)
		local hitCharacter = part:FindFirstAncestorOfClass("Model")
		local hitPlayer = hitCharacter and Players:GetPlayerFromCharacter(hitCharacter)
		processHitPlayer(player, playerState, hitPlayer, hitCharacter)
	end)
end

function StabAction.serverCleanup(_player: Player, playerState: any)
	if playerState.currentTickConnection then
		playerState.currentTickConnection:Disconnect()
		playerState.currentTickConnection = nil
	end
	if playerState.stabTouchedConn then
		playerState.stabTouchedConn:Disconnect()
		playerState.stabTouchedConn = nil
	end
	playerState.alreadyHit = {}
end

return StabAction
