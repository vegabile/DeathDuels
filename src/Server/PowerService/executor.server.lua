local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local PayloadValidator = require(ReplicatedStorage.Power.PayloadValidator)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)

local PowerService = require(script.Parent)
local TeleportMetadataService = require(ServerScriptService.RoundService.TeleportMetadataService)

local function remoteName(player: Player): string
	return `PowerAction_{player.UserId}`
end

local function fireResponse(player: Player, sequenceId: number, result: { success: boolean, reason: string? })
	NetworkRouter:Call(remoteName(player), player, {
		sequenceId = sequenceId,
		result     = result,
	})
end

local function setupPlayer(player: Player)
	local name = remoteName(player)
	NetworkRouter:CreateRemoteEvent(name)

	local loadout = TeleportMetadataService.GetLoadout(player.UserId)
	PowerService.new(player, loadout)

	NetworkRouter:Listen(name, function(firingPlayer, envelope)
		if firingPlayer ~= player then
			warn(`[POWER] Remote spoofing: {firingPlayer.Name} on {player.Name}'s remote`)
			return
		end

		local ok, reason, sequenceId = PayloadValidator.validate(envelope)
		if not ok then
			warn(`[POWER] Malformed envelope from {player.Name}: {reason}`)
			fireResponse(player, sequenceId, { success = false, reason = reason })
			return
		end

		local svc = PowerService.Get(player)
		if not svc then
			warn(`[POWER] No PowerService instance for {player.Name}`)
			fireResponse(player, sequenceId, { success = false, reason = Reasons.InvalidState })
			return
		end

		local result = svc:Activate(envelope.powerName, envelope.payload)
		fireResponse(player, sequenceId, result)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	local svc = PowerService.Get(player)
	if svc then svc:Destroy() end
	NetworkRouter:Remove(remoteName(player))
end)
