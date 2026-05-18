local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local GlobalConfigs = require(ReplicatedStorage.GlobalConfigs)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ReconnectConfig = require(ReplicatedStorage.Reconnect.ReconnectConfig)

local ReconnectService = {}

local store = MemoryStoreService:GetHashMap(ReconnectConfig.MEMORY_STORE_NAME)

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and math.floor(value) == value
end

local function now(): number
	return os.time()
end

local function getValue(key: string): any?
	local ok, result = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warn(`[ReconnectService] MemoryStore GetAsync failed for {key}: {result}`)
		return nil
	end
	return result
end

local function setValue(key: string, value: any, ttlSeconds: number): boolean
	local ok, err = pcall(function()
		store:SetAsync(key, value, ttlSeconds)
	end)
	if not ok then
		warn(`[ReconnectService] MemoryStore SetAsync failed for {key}: {err}`)
		return false
	end
	return true
end

local function hasMatchIdentity(metadata: any): boolean
	return type(metadata) == "table"
		and type(metadata.matchId) == "string"
		and metadata.matchId ~= ""
		and isFiniteNumber(metadata.placeId)
		and metadata.placeId > 0
		and type(metadata.reservedServerAccessCode) == "string"
		and metadata.reservedServerAccessCode ~= ""
end

local function getRosterEntries(metadata: any): { any }
	local entries = {}
	if type(metadata) ~= "table" then
		return entries
	end
	for _, entry in metadata.teamOnePlayers or {} do
		table.insert(entries, entry)
	end
	for _, entry in metadata.teamTwoPlayers or {} do
		table.insert(entries, entry)
	end
	return entries
end

local function normalizeLoadout(loadout: any): any?
	if type(loadout) ~= "table" then
		return nil
	end
	local powerName = loadout.Power or loadout.powerName
	return {
		knifeName = loadout.knifeName,
		gunName = loadout.gunName,
		Power = powerName,
		powerName = powerName,
	}
end

local function buildEndedTicket(metadata: any, userId: number): any
	local currentTime = now()
	return {
		status = ReconnectConfig.TICKET_STATUS.MatchEnded,
		userId = userId,
		matchId = metadata.matchId,
		placeId = metadata.placeId,
		reservedServerAccessCode = metadata.reservedServerAccessCode,
		team = 0,
		loadout = nil,
		disconnectedAt = currentTime,
		expiresAt = currentTime,
		updatedAt = currentTime,
		endedAt = currentTime,
	}
end

local function isTicketValidForReconnect(ticket: any, player: Player, expectedMatchId: string?): (boolean, string?)
	if type(ticket) ~= "table" then
		return false, "missing-ticket"
	end
	if ticket.status ~= ReconnectConfig.TICKET_STATUS.Active then
		return false, "ticket-not-active"
	end
	if not isPositiveInteger(ticket.userId) or ticket.userId ~= player.UserId then
		return false, "ticket-user-mismatch"
	end
	if type(ticket.matchId) ~= "string" or ticket.matchId == "" then
		return false, "ticket-missing-match"
	end
	if expectedMatchId ~= nil and ticket.matchId ~= expectedMatchId then
		return false, "ticket-match-mismatch"
	end
	if not isFiniteNumber(ticket.placeId) or ticket.placeId <= 0 then
		return false, "ticket-missing-place"
	end
	if type(ticket.reservedServerAccessCode) ~= "string" or ticket.reservedServerAccessCode == "" then
		return false, "ticket-missing-access-code"
	end
	if not isFiniteNumber(ticket.expiresAt) or ticket.expiresAt <= now() then
		return false, "ticket-expired"
	end
	return true, nil
end

local function isMatchRecordActive(matchRecord: any, ticket: any): (boolean, string?)
	if type(matchRecord) ~= "table" then
		return false, "match-missing"
	end
	if matchRecord.status ~= ReconnectConfig.MATCH_STATUS.Active then
		return false, "match-not-active"
	end
	if matchRecord.matchId ~= ticket.matchId then
		return false, "match-id-mismatch"
	end
	if matchRecord.placeId ~= ticket.placeId then
		return false, "match-place-mismatch"
	end
	if matchRecord.reservedServerAccessCode ~= ticket.reservedServerAccessCode then
		return false, "match-access-code-mismatch"
	end
	return true, nil
end

local function markTicketConsumed(ticket: any, userId: number)
	local currentTime = now()
	local consumed = {}
	for key, value in ticket do
		consumed[key] = value
	end
	consumed.status = ReconnectConfig.TICKET_STATUS.Consumed
	consumed.expiresAt = currentTime
	consumed.updatedAt = currentTime
	setValue(
		ReconnectConfig.ticketKey(userId),
		consumed,
		ReconnectConfig.MATCH_ENDED_TICKET_TTL_SECONDS
	)
end

function ReconnectService.RegisterMatch(metadata: any): boolean
	if not hasMatchIdentity(metadata) then
		warn("[ReconnectService] Cannot register match: metadata missing match identity")
		return false
	end

	local currentTime = now()
	return setValue(ReconnectConfig.matchKey(metadata.matchId), {
		status = ReconnectConfig.MATCH_STATUS.Active,
		matchId = metadata.matchId,
		placeId = metadata.placeId,
		reservedServerAccessCode = metadata.reservedServerAccessCode,
		updatedAt = currentTime,
	}, ReconnectConfig.MATCH_RECORD_TTL_SECONDS)
end

function ReconnectService.WriteDisconnectTicket(metadata: any, player: Player, playerState: any, loadout: any?): boolean
	if not hasMatchIdentity(metadata) then
		return false
	end
	if not player or not playerState then
		return false
	end
	local team = playerState.team
	if not isPositiveInteger(team) then
		return false
	end

	local currentTime = now()
	local ticket = {
		status = ReconnectConfig.TICKET_STATUS.Active,
		userId = player.UserId,
		matchId = metadata.matchId,
		placeId = metadata.placeId,
		reservedServerAccessCode = metadata.reservedServerAccessCode,
		team = team,
		loadout = normalizeLoadout(loadout),
		disconnectedAt = currentTime,
		expiresAt = currentTime + ReconnectConfig.TICKET_TTL_SECONDS,
		updatedAt = currentTime,
	}

	return setValue(
		ReconnectConfig.ticketKey(player.UserId),
		ticket,
		ReconnectConfig.TICKET_TTL_SECONDS
	)
end

function ReconnectService.MarkMatchEnded(metadata: any): boolean
	if not hasMatchIdentity(metadata) then
		return false
	end

	local currentTime = now()
	local ok = setValue(ReconnectConfig.matchKey(metadata.matchId), {
		status = ReconnectConfig.MATCH_STATUS.Ended,
		matchId = metadata.matchId,
		placeId = metadata.placeId,
		reservedServerAccessCode = metadata.reservedServerAccessCode,
		updatedAt = currentTime,
		endedAt = currentTime,
	}, ReconnectConfig.ENDED_MATCH_RECORD_TTL_SECONDS)

	for _, entry in getRosterEntries(metadata) do
		if type(entry) == "table" and type(entry.UserId) == "number" then
			setValue(
				ReconnectConfig.ticketKey(entry.UserId),
				buildEndedTicket(metadata, entry.UserId),
				ReconnectConfig.MATCH_ENDED_TICKET_TTL_SECONDS
			)
		end
	end

	return ok
end

function ReconnectService.ValidateReconnect(player: Player, reconnectData: any, expectedMatchId: string?): (boolean, any)
	if type(reconnectData) ~= "table" or reconnectData.reconnect ~= true then
		return false, "not-reconnect"
	end
	if type(reconnectData.matchId) ~= "string" or reconnectData.matchId == "" then
		return false, "missing-match-id"
	end
	if expectedMatchId ~= nil and reconnectData.matchId ~= expectedMatchId then
		return false, "wrong-match"
	end

	local ticket = getValue(ReconnectConfig.ticketKey(player.UserId))
	local ticketOk, ticketReason = isTicketValidForReconnect(ticket, player, expectedMatchId)
	if not ticketOk then
		return false, ticketReason
	end

	local matchRecord = getValue(ReconnectConfig.matchKey(ticket.matchId))
	local matchOk, matchReason = isMatchRecordActive(matchRecord, ticket)
	if not matchOk then
		return false, matchReason
	end

	markTicketConsumed(ticket, player.UserId)
	return true, ticket
end

function ReconnectService.ReturnPlayerToLobby(player: Player, reason: string?): boolean
	if not player or not player.Parent then
		return false
	end

	if GlobalConfigs.TEST_MODE then
		warn(`[ReconnectService] TEST_MODE active - would return {player.Name} to lobby ({reason or "no reason"})`)
		return true
	end

	for attempt = 1, RoundConfigs.RETRY_COUNT do
		local ok, err = pcall(function()
			local options = Instance.new("TeleportOptions")
			options:SetTeleportData({
				reconnectReturn = true,
				reason = reason or "ReconnectUnavailable",
				timestamp = now(),
			})
			TeleportService:TeleportAsync(RoundConfigs.LOBBY_PLACE_ID, { player }, options)
		end)
		if ok then
			return true
		end
		if attempt < RoundConfigs.RETRY_COUNT then
			local delay = RoundConfigs.EXPONENTIAL_BACKOFF_BASE * (RoundConfigs.EXPONENTIAL_BACKOFF_EXPONENT ^ (attempt - 1))
			warn(`[ReconnectService] Return teleport failed for {player.Name}; retrying in {delay}s: {err}`)
			task.wait(delay)
		else
			warn(`[ReconnectService] Return teleport exhausted for {player.Name}: {err}`)
			player:Kick(RoundConfigs.KICK_REASONS.TeleportOutFailed)
		end
	end

	return false
end

return ReconnectService
