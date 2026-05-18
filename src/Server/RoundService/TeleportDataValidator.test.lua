local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local TeleportDataValidator = require(script.Parent.TeleportDataValidator)
local nan = 0 / 0

local function validTeleportData()
	return {
		teamOnePlayers = {
			{ UserId = 101, Name = "One" },
		},
		teamTwoPlayers = {
			{ UserId = 202, Name = "Two" },
		},
		queueType = 1,
		mapName = "TestMap",
		timestamp = 123456,
		matchId = "match-teleport",
		placeId = 98765,
		reservedServerAccessCode = "access-code",
		loadouts = {
			["101"] = {
				knifeName = "Blade",
				gunName = 9001,
				Power = "dash",
			},
			["202"] = "bad-loadout",
		},
		parties = {
			alpha = {
				leaderUserId = 101,
				memberUserIds = { 101, 202 },
			},
		},
	}
end

local ok, reason, sanitized = TeleportDataValidator.validate(validTeleportData())
assert(ok == true, tostring(reason))
assert(sanitized ~= nil, "valid teleport data returns sanitized payload")
assert(sanitized.loadouts["101"].knifeName == "Blade", "sanitized loadout preserves knife")
assert(sanitized.loadouts["101"].gunName == Configs.DEFAULT_LOADOUT.gunName, "non-string gun defaults")
assert(sanitized.loadouts["101"].Power == "dash", "Power is preserved")
assert(sanitized.loadouts["101"].powerName == "dash", "powerName mirrors Power")
assert(sanitized.loadouts["202"].knifeName == Configs.DEFAULT_LOADOUT.knifeName, "bad loadout defaults")
assert(sanitized.parties.alpha.leaderUserId == 101, "party leader preserved")
assert(sanitized.parties.alpha.memberUserIds[2] == 202, "party members preserved")

local source = validTeleportData()
ok, reason, sanitized = TeleportDataValidator.validate(source)
assert(ok == true, tostring(reason))
source.teamOnePlayers[1].Name = "Mutated"
source.teamOnePlayers[1].UserId = 999
assert(sanitized.teamOnePlayers[1].Name == "One", "sanitized team names are isolated from source mutation")
assert(sanitized.teamOnePlayers[1].UserId == 101, "sanitized team user ids are isolated from source mutation")

ok, reason = TeleportDataValidator.validate(nil)
assert(ok == false and reason == "Teleport data is not a table", "non-table teleport data is rejected")

local badUserId = validTeleportData()
badUserId.teamOnePlayers[1].UserId = math.huge
ok, reason = TeleportDataValidator.validate(badUserId)
assert(ok == false and string.find(reason, "UserId is not a number", 1, true), "infinite user id is rejected")

badUserId = validTeleportData()
badUserId.teamOnePlayers[1].UserId = nan
ok, reason = TeleportDataValidator.validate(badUserId)
assert(ok == false and string.find(reason, "UserId is not a number", 1, true), "NaN user id is rejected")

local duplicate = validTeleportData()
duplicate.teamTwoPlayers[1].UserId = 101
ok, reason = TeleportDataValidator.validate(duplicate)
assert(ok == false and string.find(reason, "duplicated", 1, true), "duplicate user ids are rejected")

local badQueue = validTeleportData()
badQueue.queueType = 99
ok, reason = TeleportDataValidator.validate(badQueue)
assert(ok == false and reason == "queueType is not a valid game mode index", "bad queueType is rejected")

badQueue = validTeleportData()
badQueue.queueType = math.huge
ok, reason = TeleportDataValidator.validate(badQueue)
assert(ok == false and reason == "queueType is not a number", "infinite queueType is rejected")

local badMap = validTeleportData()
badMap.mapName = "MissingMap"
ok, reason = TeleportDataValidator.validate(badMap)
assert(ok == false and string.find(reason, "Unknown map", 1, true), "unknown map is rejected")

local badTimestamp = validTeleportData()
badTimestamp.timestamp = nan
ok, reason = TeleportDataValidator.validate(badTimestamp)
assert(ok == false and reason == "timestamp is not a number", "NaN timestamp is rejected")

local badPlace = validTeleportData()
badPlace.placeId = math.huge
ok, reason = TeleportDataValidator.validate(badPlace)
assert(ok == false and reason == "placeId is missing or not a positive number", "infinite placeId is rejected")

local badParty = validTeleportData()
badParty.parties.alpha.memberUserIds = { 303 }
ok, reason = TeleportDataValidator.validate(badParty)
assert(ok == false and string.find(reason, "not in the roster", 1, true), "party members must be in roster")

badParty = validTeleportData()
badParty.parties.alpha.leaderUserId = math.huge
ok, reason = TeleportDataValidator.validate(badParty)
assert(ok == false and string.find(reason, "leaderUserId is not a number", 1, true), "infinite party leader is rejected")

badParty = validTeleportData()
badParty.parties.alpha.memberUserIds = { nan }
ok, reason = TeleportDataValidator.validate(badParty)
assert(ok == false and string.find(reason, "memberUserIds", 1, true), "NaN party member is rejected")

local noLoadouts = validTeleportData()
noLoadouts.loadouts = nil
ok, reason, sanitized = TeleportDataValidator.validate(noLoadouts)
assert(ok == true, tostring(reason))
assert(sanitized.loadouts["101"].Power == Configs.DEFAULT_LOADOUT.Power, "missing loadouts default for team one")
assert(sanitized.loadouts["202"].Power == Configs.DEFAULT_LOADOUT.Power, "missing loadouts default for team two")

local hostileLoadout = validTeleportData()
hostileLoadout.loadouts["101"] = {
	knifeName = 123,
	gunName = false,
	Power = {},
	powerName = "",
}
ok, reason, sanitized = TeleportDataValidator.validate(hostileLoadout)
assert(ok == true, tostring(reason))
assert(sanitized.loadouts["101"].knifeName == Configs.DEFAULT_LOADOUT.knifeName, "non-string knife defaults")
assert(sanitized.loadouts["101"].gunName == Configs.DEFAULT_LOADOUT.gunName, "non-string gun defaults")
assert(sanitized.loadouts["101"].Power == Configs.DEFAULT_LOADOUT.Power, "non-string power defaults")
assert(sanitized.loadouts["101"].powerName == Configs.DEFAULT_LOADOUT.Power, "non-string powerName defaults")

print("[RoundService.TeleportDataValidator.test] passed")
return true
