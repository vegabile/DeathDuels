local ReconnectConfig = require(game:GetService("ReplicatedStorage").Reconnect.ReconnectConfig)
local ReconnectService = require(script.Parent)

__Test.MemoryStoreService:_reset()

local metadata = {
	teamOnePlayers = {
		{ UserId = 301, Name = "ReconnectOne" },
	},
	teamTwoPlayers = {
		{ UserId = 302, Name = "ReconnectTwo" },
	},
	matchId = "match-reconnect",
	placeId = 12345,
	reservedServerAccessCode = "reserved-code",
}

assert(ReconnectService.RegisterMatch(metadata) == true, "valid match metadata registers")
assert(ReconnectService.RegisterMatch({}) == false, "invalid match metadata is rejected")
assert(ReconnectService.RegisterMatch({
	matchId = "bad-place",
	placeId = math.huge,
	reservedServerAccessCode = "access",
}) == false, "non-finite placeId is rejected when registering match")

local player = Instance.new("Player")
player.Name = "ReconnectOne"
player.UserId = 301
player.Parent = game:GetService("Players")

local playerState = {
	team = 1,
}

assert(ReconnectService.WriteDisconnectTicket(metadata, player, playerState, {
	knifeName = "Knife",
	gunName = "Gun",
	powerName = "dash",
}) == true, "disconnect ticket is written")
assert(ReconnectService.WriteDisconnectTicket(metadata, player, { team = math.huge }, nil) == false, "non-finite team is rejected when writing ticket")

local ok, ticket = ReconnectService.ValidateReconnect(player, {
	reconnect = true,
	matchId = "match-reconnect",
}, "match-reconnect")
assert(ok == true, tostring(ticket))
assert(ticket.status == ReconnectConfig.TICKET_STATUS.Active, "valid reconnect returns active ticket")
assert(ticket.loadout.Power == "dash" and ticket.loadout.powerName == "dash", "ticket normalizes powerName")

ok, ticket = ReconnectService.ValidateReconnect(player, {
	reconnect = true,
	matchId = "match-reconnect",
}, "match-reconnect")
assert(ok == false and ticket == "ticket-not-active", "consumed ticket cannot be reused")

local store = __Test.MemoryStoreService:GetHashMap(ReconnectConfig.MEMORY_STORE_NAME)
store:SetAsync(ReconnectConfig.matchKey("poisoned-match"), {
	status = ReconnectConfig.MATCH_STATUS.Active,
	matchId = "poisoned-match",
	placeId = 12345,
	reservedServerAccessCode = "reserved-code",
}, 60)
store:SetAsync(ReconnectConfig.ticketKey(player.UserId), {
	status = ReconnectConfig.TICKET_STATUS.Active,
	matchId = "poisoned-match",
	placeId = 12345,
	reservedServerAccessCode = "reserved-code",
	expiresAt = os.time() + 60,
}, 60)
ok, ticket = ReconnectService.ValidateReconnect(player, {
	reconnect = true,
	matchId = "poisoned-match",
}, "poisoned-match")
assert(ok == false and ticket == "ticket-user-mismatch", "ticket missing user id is rejected")

store:SetAsync(ReconnectConfig.ticketKey(player.UserId), {
	status = ReconnectConfig.TICKET_STATUS.Active,
	userId = player.UserId,
	matchId = "poisoned-match",
	placeId = math.huge,
	reservedServerAccessCode = "reserved-code",
	expiresAt = os.time() + 60,
}, 60)
ok, ticket = ReconnectService.ValidateReconnect(player, {
	reconnect = true,
	matchId = "poisoned-match",
}, "poisoned-match")
assert(ok == false and ticket == "ticket-missing-place", "ticket with infinite place id is rejected")

store:SetAsync(ReconnectConfig.ticketKey(player.UserId), {
	status = ReconnectConfig.TICKET_STATUS.Active,
	userId = player.UserId,
	matchId = "poisoned-match",
	placeId = 12345,
	reservedServerAccessCode = "reserved-code",
	expiresAt = 0 / 0,
}, 60)
ok, ticket = ReconnectService.ValidateReconnect(player, {
	reconnect = true,
	matchId = "poisoned-match",
}, "poisoned-match")
assert(ok == false and ticket == "ticket-expired", "ticket with NaN expiry is rejected")

local wrongPlayer = Instance.new("Player")
wrongPlayer.Name = "Wrong"
wrongPlayer.UserId = 999
wrongPlayer.Parent = game:GetService("Players")
ok, ticket = ReconnectService.ValidateReconnect(wrongPlayer, {
	reconnect = false,
	matchId = "match-reconnect",
}, "match-reconnect")
assert(ok == false and ticket == "not-reconnect", "non-reconnect data is rejected early")

assert(ReconnectService.MarkMatchEnded(metadata) == true, "MarkMatchEnded writes ended state")
ok, ticket = ReconnectService.ValidateReconnect(player, {
	reconnect = true,
	matchId = "match-reconnect",
}, "match-reconnect")
assert(ok == false and ticket == "ticket-not-active", "ended match ticket is not reconnectable")

player.Parent = nil
assert(ReconnectService.ReturnPlayerToLobby(player, "Gone") == false, "missing player parent is not teleported")
player.Parent = game:GetService("Players")
assert(ReconnectService.ReturnPlayerToLobby(player, "Test") == true, "TEST_MODE lobby return succeeds")

print("[ReconnectService.test] passed")
return true
