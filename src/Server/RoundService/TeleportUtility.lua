local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local Configs = require(ReplicatedStorage.Round.Configs)

local TeleportUtility = {}

function TeleportUtility.buildReturnPayload(playerStates: { [Player]: any }, roundResults: { any }, winningTeam: number?, disconnectedStats: { [string]: any }?)
	local serializedStats = {}

	if disconnectedStats then
		for odUserId, data in disconnectedStats do
			serializedStats[odUserId] = data
		end
	end

	for player, state in playerStates do
		serializedStats[tostring(player.UserId)] = state:Serialize()
	end

	return {
		roundResults = roundResults,
		winningTeam = winningTeam,
		playerStats = serializedStats,
	}
end

function TeleportUtility._teleportPlayers(players: { Player }, placeId: number, teleportData: {}): (boolean, string?)
	--// TEST_MODE: suppress TeleportAsync so the Studio session stays open
	if GlobalConfigs.TEST_MODE then
		warn("[TeleportUtility] TEST_MODE active — skipping TeleportAsync")
		return true, nil
	end

	if #players == 0 then
		warn("[TeleportUtility] No players to teleport")
		return false, "No players to teleport"
	end

	if placeId == 0 then
		warn("[TeleportUtility] LOBBY_PLACE_ID is 0 — set it in Shared/Round/Configs.lua")
		return false, "LOBBY_PLACE_ID not configured"
	end

	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData(teleportData)
		TeleportService:TeleportAsync(placeId, players, options)
	end)

	if not ok then
		warn(`[TeleportUtility] Teleport failed: {err}`)
		return false, err
	end

	return true, nil
end

function TeleportUtility.teleportPlayersWithRetry(players: { Player }, placeId: number, teleportData: {}): (boolean, string?)
	for attempt = 1, Configs.RETRY_COUNT do
		local ok, err = TeleportUtility._teleportPlayers(players, placeId, teleportData)
		if ok then
			return true, nil
		end

		if attempt < Configs.RETRY_COUNT then
			local delay = Configs.EXPONENTIAL_BACKOFF_BASE * (Configs.EXPONENTIAL_BACKOFF_EXPONENT ^ (attempt - 1))
			warn(`[TeleportUtility] Attempt {attempt}/{Configs.RETRY_COUNT} failed, retrying in {delay}s: {err}`)
			task.wait(delay)
		else
			warn(`[TeleportUtility] All {Configs.RETRY_COUNT} attempts exhausted: {err}`)
			return false, err
		end
	end

	return false, "Retry loop exited unexpectedly"
end

return TeleportUtility
