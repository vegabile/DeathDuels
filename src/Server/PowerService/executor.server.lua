local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local PayloadValidator = require(ReplicatedStorage.Power.PayloadValidator)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local SharedTypes = require(ReplicatedStorage.Power.Types)

local PowerService = require(script.Parent)

NetworkRouter:CreateRemoteEvent("PowerBroadcast")

type PowerResult = SharedTypes.PowerResult

local function remoteName(player: Player): string
	return `PowerAction_{player.UserId}`
end

local function fireResponse(player: Player, sequenceId: number, result: PowerResult)
	NetworkRouter:Call(remoteName(player), player, {
		sequenceId = sequenceId,
		result     = result,
	})
end

local function setupPlayer(player: Player)
	
	
	if PowerService.Get(player) ~= nil then return end

	local name = remoteName(player)
	NetworkRouter:CreateRemoteEvent(name)

	PowerService.new(player)

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

	local name = remoteName(player)
	local remote = NetworkRouter:Get(name)
	NetworkRouter:Remove(name)
	if remote then remote:Destroy() end
end)
