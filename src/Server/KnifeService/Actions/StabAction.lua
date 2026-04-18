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
StabAction.animationId = SharedConfigs.StabAnimationId

function StabAction.serverExecute(player: Player, playerState: any, _directionVector: Vector3?)
	playerState.alreadyHit = {}
	local startTime = tick()

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	playerState.currentTickConnection = RunService.Heartbeat:Connect(function()
		if tick() - startTime >= StabAction.duration then
			if playerState.currentTickConnection then
				playerState.currentTickConnection:Disconnect()
				playerState.currentTickConnection = nil
			end
			playerState.alreadyHit = {}
			return
		end

		local character = player.Character
		if not character then return end

		local knifeTool = KnifeUtility.findKnifeTool(character)
		if not knifeTool then return end

		local hitbox = knifeTool:FindFirstChild("Hitbox")
		if not hitbox then return end

		overlapParams.FilterDescendantsInstances = { character }

		local parts = workspace:GetPartsInPart(hitbox, overlapParams)
		local attackerRoot = character:FindFirstChild("HumanoidRootPart")
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
end

function StabAction.serverCleanup(player: Player, playerState: any)
	if playerState.currentTickConnection then
		playerState.currentTickConnection:Disconnect()
		playerState.currentTickConnection = nil
	end
	playerState.alreadyHit = {}
end

return StabAction
