local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
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

local function sanitizePositiveInteger(value: any): number
	if not isFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.floor(value)
end

local function copyQuestDelta(source)
	local quest = {}
	if type(source) ~= "table" then return quest end

	for key, value in source do
		local amount = sanitizePositiveInteger(value)
		if type(key) == "string" and amount > 0 then
			quest[key] = amount
		end
	end
	return quest
end

local function addQuestDelta(quest, key: string, amount: number)
	amount = sanitizePositiveInteger(amount)
	if amount <= 0 then return end
	quest[key] = (quest[key] or 0) + amount
end

local function hasFriendInRoster(player: Player, rosterPlayers: { Player }?): boolean
	if type(rosterPlayers) ~= "table" then return false end
	if type((player :: any).IsFriendsWithAsync) ~= "function" then return false end

	for _, otherPlayer in rosterPlayers do
		if otherPlayer ~= player and type((otherPlayer :: any).UserId) == "number" then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWithAsync(otherPlayer.UserId)
			end)
			if ok and isFriend == true then
				return true
			end
		end
	end
	return false
end

local function buildQuestDelta(sourceQuest, player: Player?, playSeconds: number, rosterPlayers: { Player }?)
	local quest = copyQuestDelta(sourceQuest)
	addQuestDelta(quest, "PlaySeconds", playSeconds)
	if player and hasFriendInRoster(player, rosterPlayers) then
		addQuestDelta(quest, "FriendPlaySeconds", playSeconds)
	end
	if next(quest) == nil then
		return nil
	end
	return quest
end

local function getPlaySeconds(matchStartedAt: number?): number
	if not isFiniteNumber(matchStartedAt) then return 0 end
	return sanitizePositiveInteger(os.time() - matchStartedAt)
end

local function shouldDebugReturnTeleportData(): boolean
	return GlobalConfigs.TEST_MODE or Configs.DEBUG_RETURN_TELEPORT_DATA == true
end

local function buildPlayerDebugList(players: { Player })
	local list = {}
	for index, player in players do
		list[index] = {
			name = player.Name,
			userId = player.UserId,
			parent = if player.Parent then player.Parent:GetFullName() else nil,
		}
	end
	return list
end

function TeleportUtility.buildReturnPayload(playerStates: { [Player]: any }, roundResults: { any }, winningTeam: number?, disconnectedStats: { [string]: any }?, matchId: string?, matchStartedAt: number?, rosterPlayers: { Player }?)
	local delta = {}
	local playSeconds = getPlaySeconds(matchStartedAt)

	for player, state in playerStates do
		local rawKills = if type(state.GetMatchStat) == "function" then state:GetMatchStat("kills") else state:GetStat("kills")
		local kills = sanitizeKills(rawKills)
		local entry = {
			coinsEarned   = kills * Configs.COINS_PER_KILL,
			xpEarned      = kills * Configs.XP_PER_KILL,
			actionId      = matchId and `match:{matchId}:player:{player.UserId}` or nil,
			kills         = kills,
			matchesPlayed = 1,
		}
		entry.quest = buildQuestDelta(state.quest, player, playSeconds, rosterPlayers)
		delta[tostring(player.UserId)] = entry
	end

	if disconnectedStats then
		for odUserId, data in disconnectedStats do
			local stats = data.matchStats or data.stats
			local kills = sanitizeKills(stats and stats.kills or 0)
			local entry = {
				coinsEarned   = kills * Configs.COINS_PER_KILL,
				xpEarned      = kills * Configs.XP_PER_KILL,
				actionId      = matchId and `match:{matchId}:player:{odUserId}` or nil,
				kills         = kills,
				matchesPlayed = 1,
			}
			entry.quest = buildQuestDelta(data.quest, nil, playSeconds, rosterPlayers)
			delta[odUserId] = entry
		end
	end

	return {
		delta = delta,
		returnSpawnPartName = Configs.POST_ROUND_SPAWN_PART,
	}
end

function TeleportUtility.debugReturnTeleportData(players: { Player }, placeId: number, teleportData: {})
	if not shouldDebugReturnTeleportData() then
		return
	end

	local snapshot = {
		kind = "ReturnTeleportDebugSnapshot",
		mockTeleportBackData = GlobalConfigs.TEST_MODE,
		studioTeleportSkipped = GlobalConfigs.TEST_MODE,
		willCallTeleportAsync = not GlobalConfigs.TEST_MODE,
		targetPlaceId = placeId,
		playerCount = #players,
		players = buildPlayerDebugList(players),
		teleportOptionsData = teleportData,
	}

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(snapshot)
	end)

	if ok then
		warn(`[TeleportUtility] Return teleport debug payload: {encoded}`)
	else
		warn(`[TeleportUtility] Return teleport debug payload could not be JSON encoded: {encoded}`)
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
	TeleportUtility.debugReturnTeleportData(players, placeId, teleportData)

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
