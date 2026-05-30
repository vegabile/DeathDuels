local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local Configs = require(ReplicatedStorage.Round.Configs)

local TeleportUtility = {}

local rewardStore = MemoryStoreService:GetHashMap(Configs.MATCH_REWARD_STORE_NAME)

local function rewardKey(userId: number): string
	return `{Configs.MATCH_REWARD_KEY_PREFIX}{tostring(userId)}`
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sanitizeKills(value: any): number
	if not isFiniteNumber(value) or value < 0 then
		return 0
	end
	return math.floor(value)
end

function TeleportUtility.buildReturnPayload(playerStates: { [Player]: any }, roundResults: { any }, winningTeam: number?, disconnectedStats: { [string]: any }?, matchId: string?)
	local delta = {}

	for player, state in playerStates do
		local rawKills = if type(state.GetMatchStat) == "function" then state:GetMatchStat("kills") else state:GetStat("kills")
		local kills = sanitizeKills(rawKills)
		delta[tostring(player.UserId)] = {
			coinsEarned   = kills * Configs.COINS_PER_KILL,
			xpEarned      = kills * Configs.XP_PER_KILL,
			actionId      = matchId and `match:{matchId}:player:{player.UserId}` or nil,
			kills         = kills,
			matchesPlayed = 1,
		}
	end

	if disconnectedStats then
		for odUserId, data in disconnectedStats do
			local stats = data.matchStats or data.stats
			local kills = sanitizeKills(stats and stats.kills or 0)
			delta[odUserId] = {
				coinsEarned   = kills * Configs.COINS_PER_KILL,
				xpEarned      = kills * Configs.XP_PER_KILL,
				actionId      = matchId and `match:{matchId}:player:{odUserId}` or nil,
				kills         = kills,
				matchesPlayed = 1,
			}
		end
	end

	return {
		delta = delta,
		returnSpawnPartName = Configs.POST_ROUND_SPAWN_PART,
		--// Non-amount marker the lobby keys post-round spawn + reconnect
		--// suppression off (F005). Amounts now live in the MemoryStore record.
		reconnectReturn = true,
	}
end

--// Writes the server-authoritative reward record for each player to the shared
--// MemoryStore HashMap the lobby consumes (F005). Called BEFORE the teleport so
--// the record is in place when the player lands. Each record carries a one-time
--// token (the lobby's idempotency uuid). Per-key failures warn (never silent) so
--// a single MemoryStore error cannot strand the whole teleport.
function TeleportUtility.writeRewardRecords(payload: { delta: { [string]: any } }, matchId: string?)
	if GlobalConfigs.TEST_MODE then
		warn("[TeleportUtility] TEST_MODE active — skipping reward record write")
		return
	end
	if type(payload) ~= "table" or type(payload.delta) ~= "table" then
		warn("[TeleportUtility] writeRewardRecords: payload.delta missing — no reward records written")
		return
	end

	local matchJobId = game.JobId
	local placeId = game.PlaceId
	local writtenAt = os.time()

	for userIdString, entry in payload.delta do
		local userId = tonumber(userIdString)
		if type(userId) ~= "number" then
			warn(`[TeleportUtility] writeRewardRecords: non-numeric userId '{tostring(userIdString)}' — skipping`)
			continue
		end
		if type(entry) ~= "table" then
			warn(`[TeleportUtility] writeRewardRecords: delta entry for {userIdString} not a table — skipping`)
			continue
		end

		local record = {
			token = HttpService:GenerateGUID(false),
			matchId = matchId,
			matchJobId = matchJobId,
			placeId = placeId,
			userId = userId,
			writtenAt = writtenAt,
			reward = {
				coinsEarned   = entry.coinsEarned,
				xpEarned      = entry.xpEarned,
				kills         = entry.kills,
				wins          = entry.wins,
				losses        = entry.losses,
				deaths        = entry.deaths,
				matchesPlayed = entry.matchesPlayed,
			},
		}

		local ok, err = pcall(function()
			rewardStore:SetAsync(rewardKey(userId), record, Configs.MATCH_REWARD_TTL_SECONDS)
		end)
		if not ok then
			warn(`[TeleportUtility] writeRewardRecords: SetAsync failed for {userIdString}: {tostring(err)}`)
		end
	end
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
