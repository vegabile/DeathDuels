local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)
local PlayerReadiness = require(script.Parent.PlayerReadiness)

PlayerReadiness._reset()

local player = Instance.new("Player")
player.Name = "ReadyPlayer"
player.UserId = 501

assert(PlayerReadiness.getRecord(player) == nil, "player starts without readiness record")
assert(PlayerReadiness.isComplete(player) == false, "player without record is incomplete")

local record = PlayerReadiness.ensureRecord(player)
assert(record.player == player, "ensureRecord stores player")
assert(record.loadAttempt == 0, "new record starts at load attempt zero")
assert(PlayerReadiness.ensureRecord(player) == record, "ensureRecord returns existing record")

PlayerReadiness.recordFact(player, "UnknownFact")
assert(record.facts.UnknownFact == nil, "unknown facts are ignored")

PlayerReadiness.recordFact(player, "ProfileLoaded")
PlayerReadiness.recordFact(player, "LoadoutResolved")
assert(PlayerReadiness.isComplete(player) == false, "recorded non-character facts are not enough")

local token = PlayerReadiness.beginCharacterLoad(player)
assert(token == 1 and record.loadAttempt == 1, "beginCharacterLoad increments token")
PlayerReadiness.recordCharacterFact(player, token + 1, "CharacterLoaded")
assert(record.facts.CharacterLoaded == nil, "stale character token is ignored")
PlayerReadiness.recordCharacterFact(player, token, "CharacterLoaded")
PlayerReadiness.recordCharacterFact(player, token, "CharacterUsable")
assert(record.facts.CharacterLoaded == true and record.facts.CharacterUsable == true, "current character token records facts")

local character = Instance.new("Model")
character.Name = "Character"
local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.Name = "Humanoid"
humanoid.Parent = character
player.Character = character

assert(PlayerReadiness.isComplete(player) == true, "all required facts plus character shape are complete")
PlayerReadiness.clearFact(player, "CharacterUsable")
assert(PlayerReadiness.isComplete(player) == false, "clearing a required fact makes player incomplete")

local missing = PlayerReadiness.missingFacts(player)
assert(#missing == 1 and missing[1] == "CharacterUsable", "missingFacts reports cleared fact")

for _, factName in Configs.REQUIRED_FACTS do
	PlayerReadiness.recordFact(player, factName)
end
assert(PlayerReadiness.isComplete(player) == true, "recordFact can restore character facts")

PlayerReadiness.destroyRecord(player)
assert(PlayerReadiness.getRecord(player) == nil, "destroyRecord removes readiness record")

print("[RoundService.PlayerReadiness.test] passed")
return true
