local TeleportMetadataService = require(script.Parent.TeleportMetadataService)

local metadata = {
	teamOnePlayers = {
		{ UserId = 11, Name = "One" },
	},
	teamTwoPlayers = {
		{ UserId = 22, Name = "Two" },
	},
	queueType = 1,
	mapName = "TestMap",
	timestamp = 100,
	matchId = "match-meta",
	placeId = 777,
	reservedServerAccessCode = "access-meta",
	loadouts = {
		["11"] = { knifeName = "KnifeA", gunName = "GunA", Power = "sprint", powerName = "sprint" },
	},
	parties = {
		squad = {
			leaderUserId = 11,
			memberUserIds = { 22 },
		},
	},
}

TeleportMetadataService.Initialize(metadata)

assert(TeleportMetadataService.GetTeam({ UserId = 11, Name = "One" }) == 1, "team one lookup works")
assert(TeleportMetadataService.GetTeam({ UserId = 22, Name = "Two" }) == 2, "team two lookup works")
assert(TeleportMetadataService.GetQueueType() == 1, "queue type is stored")
assert(TeleportMetadataService.GetMapName() == "TestMap", "map name is stored")
assert(TeleportMetadataService.GetTimestamp() == 100, "timestamp is stored")
assert(TeleportMetadataService.GetMatchId() == "match-meta", "match id is stored")
assert(TeleportMetadataService.GetPlaceId() == 777, "place id is stored")
assert(TeleportMetadataService.GetReservedServerAccessCode() == "access-meta", "access code is stored")
assert(TeleportMetadataService.GetLoadout(11).Power == "sprint", "loadout lookup works")

TeleportMetadataService.SetTeam(33, 2)
assert(TeleportMetadataService.GetTeam({ UserId = 33, Name = "Late" }) == 2, "SetTeam stores dynamic team")

TeleportMetadataService.SetLoadout(22, { knifeName = "KnifeB", gunName = "GunB", Power = "dash", powerName = "dash" })
assert(TeleportMetadataService.GetLoadout(22).Power == "dash", "SetLoadout stores dynamic loadout")

assert(TeleportMetadataService.GetPartyIdForUserId(11) == "squad", "leader has party id")
assert(TeleportMetadataService.GetPartyIdForUserId(22) == "squad", "member has party id")
local party = TeleportMetadataService.GetPartyForUserId(22)
assert(party.leaderUserId == 11 and party.memberUserIds[1] == 22, "party lookup returns party details")

local parties = TeleportMetadataService.GetParties()
parties.squad.memberUserIds[1] = 999
assert(TeleportMetadataService.GetPartyForUserId(22).memberUserIds[1] == 22, "GetParties returns a copy")

print("[RoundService.TeleportMetadataService.test] passed")
return true
