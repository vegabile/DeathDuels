local ReconnectConfig = {}

ReconnectConfig.MEMORY_STORE_NAME = "DeathDuelsReconnect"
ReconnectConfig.TICKET_KEY_PREFIX = "ReconnectTicket:"
ReconnectConfig.MATCH_KEY_PREFIX = "ReconnectMatch:"

ReconnectConfig.TICKET_TTL_SECONDS = 45
ReconnectConfig.MATCH_RECORD_TTL_SECONDS = 20 * 60
ReconnectConfig.ENDED_MATCH_RECORD_TTL_SECONDS = 2 * 60
ReconnectConfig.MATCH_ENDED_TICKET_TTL_SECONDS = 45

ReconnectConfig.TICKET_STATUS = {
	Active = "Active",
	MatchEnded = "MatchEnded",
	Consumed = "Consumed",
}

ReconnectConfig.MATCH_STATUS = {
	Active = "Active",
	Ended = "Ended",
}

function ReconnectConfig.ticketKey(userId: number): string
	return `{ReconnectConfig.TICKET_KEY_PREFIX}{tostring(userId)}`
end

function ReconnectConfig.matchKey(matchId: string): string
	return `{ReconnectConfig.MATCH_KEY_PREFIX}{matchId}`
end

return ReconnectConfig
