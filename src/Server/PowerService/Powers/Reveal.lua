local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local Configs = require(script.Parent.Parent.Configs)
local cfg = Configs.POWERS.Reveal

local Reveal = {}

Reveal.name = "reveal"
Reveal.cooldown = cfg.cooldown

function Reveal.validatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
	return true, nil
end

function Reveal:Execute(player: Player, _payload: any): boolean
	local myTeam = TeleportMetadataService.GetTeam(player)
	if not myTeam then warn(`[Reveal] No team for {player.Name}`); return false end

	local enemies: { Player } = {}
	for _, other in Players:GetPlayers() do
		if other == player then continue end
		local team = TeleportMetadataService.GetTeam(other)
		if team == nil or team == myTeam then continue end
		local char = other.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		table.insert(enemies, other)
	end

	if #enemies == 0 then
		warn(`[Reveal] No alive enemies to reveal for {player.Name}`)
		return false
	end

	local target = enemies[math.random(1, #enemies)]
	NetworkRouter:Call("PowerBroadcast", player, {
		effectType = "Reveal",
		targetCharacter = target.Character,
		durationSec = cfg.durationSec,
	})

	return true
end

return Reveal
