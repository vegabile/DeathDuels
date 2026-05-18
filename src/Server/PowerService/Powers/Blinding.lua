local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local Configs = require(script.Parent.Parent.Configs)
local RoundScope = require(script.Parent.Parent.RoundScope)
local cfg = Configs.POWERS.Blinding

local Blinding = {}

Blinding.name = "blinding"
Blinding.cooldown = cfg.cooldown

function Blinding.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

local function pickTarget(player: Player, originCFrame: CFrame): (Player?, Vector3)
	local myTeam = TeleportMetadataService.GetTeam(player)
	local lookVec = originCFrame.LookVector
	local originPos = originCFrame.Position

	local bestPlayer, bestAngle = nil, cfg.aimAssistCone
	for _, other in Players:GetPlayers() do
		if other == player then continue end
		local team = TeleportMetadataService.GetTeam(other)
		if team == nil or team == myTeam then continue end
		local char = other.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then continue end

		local delta = (hrp.Position - originPos)
		if delta.Magnitude < 0.01 then continue end
		local angle = math.acos(math.clamp(lookVec:Dot(delta.Unit), -1, 1))
		if angle < bestAngle then
			bestAngle = angle
			bestPlayer = other
		end
	end

	if bestPlayer then
		local targetChar = bestPlayer.Character
		local tgtHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
		if tgtHrp and tgtHrp:IsA("BasePart") then
			return bestPlayer, (tgtHrp.Position - originPos).Unit
		end
	end
	return nil, lookVec
end

function Blinding:Execute(player: Player, _payload: any)
	local char = player.Character
	if not char then warn(`[Blinding] No character for {player.Name}`); return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then warn(`[Blinding] No HRP for {player.Name}`); return end

	local targetPlayer, direction = pickTarget(player, hrp.CFrame)

	local projectile = Instance.new("Part")
	projectile.Name = "BlindingProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(2, 2, 2)
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.Massless = true
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.new(1, 1, 0.8)
	projectile.Position = hrp.Position + direction * 2
	projectile.Parent = workspace
	RoundScope.Register(projectile)
	projectile.AssemblyLinearVelocity = direction * cfg.projectileSpeed

	local hit = false
	projectile.Touched:Connect(function(other)
		if hit then return end
		local model = other:FindFirstAncestorOfClass("Model")
		if not model then return end
		local hitPlayer = Players:GetPlayerFromCharacter(model)
		if not hitPlayer or hitPlayer == player then return end
		if TeleportMetadataService.GetTeam(hitPlayer) == TeleportMetadataService.GetTeam(player) then return end

		hit = true
		NetworkRouter:Call("PowerBroadcast", hitPlayer, {
			effectType = "Blind",
			durationSec = cfg.blindDurationSec,
		})
		if projectile and projectile.Parent then projectile:Destroy() end
	end)

	Debris:AddItem(projectile, cfg.projectileLifetime)

	if targetPlayer == nil then
		warn(`[Blinding] No enemy in aim-assist cone; firing straight for {player.Name}`)
	end
end

return Blinding
