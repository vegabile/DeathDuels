local TeleportUtility = require(script.Parent.TeleportUtility)
local GlobalConfigs = require(game:GetService("ReplicatedStorage").GlobalConfigs)
local nan = 0 / 0

local fakePlayer = {
	UserId = 42,
	Name = "Rewarded",
	Parent = game,
}

local fakeState = {
	GetMatchStat = function(_, key)
		if key == "kills" then
			return 3
		end
		return 0
	end,
}

local fallbackPlayer = {
	UserId = 43,
	Name = "Fallback",
	Parent = game,
}

local fallbackState = {
	GetStat = function(_, key)
		if key == "kills" then
			return 1.9
		end
		return 0
	end,
}

local hostilePlayer = {
	UserId = 44,
	Name = "Hostile",
	Parent = game,
}

local hostileState = {
	GetMatchStat = function()
		return math.huge
	end,
}

local payload = TeleportUtility.buildReturnPayload({
	[fakePlayer] = fakeState,
	[fallbackPlayer] = fallbackState,
	[hostilePlayer] = hostileState,
}, {}, 1, {
	["99"] = {
		matchStats = {
			kills = 2,
		},
	},
	["100"] = {
		matchStats = {
			kills = "bad",
		},
	},
	["101"] = {
		stats = {
			kills = nan,
		},
	},
}, "match-abc")

assert(payload.delta["42"].kills == 3, "connected player uses match kills")
assert(payload.delta["42"].actionId == "match:match-abc:player:42", "connected player action id includes match")
assert(payload.delta["42"].coinsEarned == 30, "connected player coin rewards scale by kills")
assert(payload.delta["42"].xpEarned == 300, "connected player xp rewards scale by kills")
assert(payload.delta["43"].kills == 1, "state without GetMatchStat falls back to floored round kills")
assert(payload.delta["44"].kills == 0, "non-finite connected kills are clamped to zero")
assert(payload.delta["99"].kills == 2, "disconnected player uses serialized match kills")
assert(payload.delta["100"].kills == 0, "string disconnected kills are clamped to zero")
assert(payload.delta["101"].kills == 0, "NaN disconnected kills are clamped to zero")
assert(payload.delta["99"].actionId == "match:match-abc:player:99", "disconnected player action id includes match")
assert(payload.returnSpawnPartName == "PostRoundSpawnPart", "payload includes return spawn")

local ok, reason = TeleportUtility._teleportPlayers({}, 0, {})
assert(ok == true and reason == nil, "TEST_MODE skips teleport validation and succeeds")

GlobalConfigs.TEST_MODE = false
ok, reason = TeleportUtility._teleportPlayers({}, 123, {})
assert(ok == false and reason == "No players to teleport", "empty teleport list is rejected outside TEST_MODE")
ok, reason = TeleportUtility._teleportPlayers({ fakePlayer }, 0, {})
assert(ok == false and reason == "LOBBY_PLACE_ID not configured", "zero place id is rejected outside TEST_MODE")
GlobalConfigs.TEST_MODE = true

print("[RoundService.TeleportUtility.test] passed")
return true
