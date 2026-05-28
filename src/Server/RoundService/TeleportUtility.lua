local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local Configs = require(ReplicatedStorage.Round.Configs)

local TeleportUtility = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sanitizeKills(value: any): number
	if not isFiniteNumber(value) or value < 0 then
		return 0
	end
	return math.floor(value)
end

local function sanitizeQuest(quest: any): { [string]: number }?
	if type(quest) ~= "table" then
		return nil
	end
	local sanitized = {}
	for key, value in quest do
		if type(key) == "string" and isFiniteNumber(value) and value > 0 then
			sanitized[key] = math.floor(value)
		end
	end
	return if next(sanitized) ~= nil then sanitized else nil
end

function TeleportUtility.buildReturnPayload(playerStates: { [Player]: any }, roundResults: { any }, winningTeam: number?, disconnectedStats: { [string]: any }?, matchId: string?)
	local delta = {}

	for player, state in playerStates do
		local rawKills = if type(state.GetMatchStat) == "function" then state:GetMatchStat("kills") else state:GetStat("kills")
		local kills = sanitizeKills(rawKills)
		local quest = sanitizeQuest(state.quest)
		delta[tostring(player.UserId)] = {
			coinsEarned   = kills * Configs.COINS_PER_KILL,
			xpEarned      = kills * Configs.XP_PER_KILL,
			actionId      = matchId and `match:{matchId}:player:{player.UserId}` or nil,
			kills         = kills,
			matchesPlayed = 1,
			quest         = quest,
		}
	end

	if disconnectedStats then
		for odUserId, data in disconnectedStats do
			local stats = data.matchStats or data.stats
			local kills = sanitizeKills(stats and stats.kills or 0)
			local quest = sanitizeQuest(data.quest)
			delta[odUserId] = {
				coinsEarned   = kills * Configs.COINS_PER_KILL,
				xpEarned      = kills * Configs.XP_PER_KILL,
				actionId      = matchId and `match:{matchId}:player:{odUserId}` or nil,
				kills         = kills,
				matchesPlayed = 1,
				quest         = quest,
			}
		end
	end

	return {
		delta = delta,
		returnSpawnPartName = Configs.POST_ROUND_SPAWN_PART,
	}
end

function TeleportUtility._teleportPlayers(players: { Player }, placeId: number, teleportData: {}): (boolean, string?)
	
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
			for _, player in players do
				if player.Parent then
					player:Kick(Configs.KICK_REASONS.TeleportOutFailed)
				end
			end
			return false, err
		end
	end

	return false, "Retry loop exited unexpectedly"
end

return TeleportUtility
