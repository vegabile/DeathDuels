local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local KnifeService = require(script.Parent)

__Test.clearDelayedTasks()
__Test.setTick(2000)

local function makePlayer(userId, withKnife)
	local player = Instance.new("Player")
	player.Name = `KnifeTester{userId}`
	player.UserId = userId
	player.Parent = Players

	local character = Instance.new("Model")
	character.Name = "Character"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Vector3.new(0, 0, 0)
	root.CFrame = CFrame.new(root.Position)
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.Parent = character
	if withKnife then
		local tool = Instance.new("Tool")
		tool.Name = "TestKnife"
		tool:SetAttribute("IsKnife", true)
		local hitbox = Instance.new("Part")
		hitbox.Name = "Hitbox"
		hitbox.Parent = tool
		tool.Parent = character
	end
	player.Character = character

	return player
end

local function stab(sequenceId)
	return {
		desiredAction = "Stab",
		sequenceId = sequenceId,
	}
end

local player = makePlayer(6201, true)
KnifeService.OnPlayerAdded(player)
local remote = NetworkRouter:Get(KnifeService._getRemoteName(player))

local spoofer = makePlayer(6202, true)
remote.OnServerEvent:Fire(spoofer, stab(1))
assert(remote._lastFire == nil, "spoofed knife remote does not send a response on the victim remote")

ServerEventBus:FireSticky("RoundStateChanged", RoundConfigs.GAME_STATES.WaitingForPlayers)
KnifeService._handleActionRequest(player, stab(2))
assert(remote._lastFire[2].payloadType == "StateOverride", "knife action outside active round is rejected")
assert(remote._lastFire[2].sequenceId == 2, "state override preserves sanitized sequence id")

ServerEventBus:FireSticky("RoundStateChanged", RoundConfigs.GAME_STATES.RoundActive)
player:SetAttribute("CombatDisabled", true)
KnifeService._handleActionRequest(player, stab(3))
assert(remote._lastFire[2].payloadType == "StateOverride", "CombatDisabled rejects knife action")
player:SetAttribute("CombatDisabled", nil)

KnifeService._handleActionRequest(player, { desiredAction = "Throw", sequenceId = 4, restOrigin = Vector3.new(0, 0, 0) })
assert(remote._lastFire[2].payloadType == "StateOverride", "malformed throw payload is rejected before action execution")
assert(remote._lastFire[2].sequenceId == 4, "malformed throw keeps valid sequence")

player:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, nil)
KnifeService._handleActionRequest(player, stab(5))
assert(remote._lastFire[2].payloadType == "StateOverride", "combat-ineligible knife action is rejected")
assert(remote._lastFire[2].sequenceId == 5, "combat-ineligible override preserves sequence")

player:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, false)
KnifeService._handleActionRequest(player, stab(6))
assert(remote._lastFire[2].payloadType == "StateOverride", "false combat eligibility rejects knife action")
assert(remote._lastFire[2].sequenceId == 6, "false combat eligibility override preserves sequence")

player:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, true)
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
humanoid.Health = 0
KnifeService._handleActionRequest(player, stab(7))
assert(remote._lastFire[2].payloadType == "StateOverride", "dead humanoid rejects knife action")
assert(remote._lastFire[2].sequenceId == 7, "dead humanoid override preserves sequence")
humanoid.Health = 100

local noKnifePlayer = makePlayer(6203, false)
KnifeService.OnPlayerAdded(noKnifePlayer)
local noKnifeRemote = NetworkRouter:Get(KnifeService._getRemoteName(noKnifePlayer))
noKnifePlayer:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, true)
KnifeService._handleActionRequest(noKnifePlayer, stab(8))
assert(noKnifeRemote._lastFire[2].payloadType == "StateOverride", "player without knife is rejected")
KnifeService.OnPlayerRemoving(noKnifePlayer)

remote._lastFire = nil
KnifeService._handleActionRequest(player, stab(9))
assert(remote._lastFire == nil, "accepted knife action does not send immediate state override")
__Test.setTick(2000.1)
KnifeService._handleActionRequest(player, stab(10))
assert(remote._lastFire[2].payloadType == "StateOverride", "rapid knife repeat is rate-limited")
assert(remote._lastFire[2].sequenceId == 10, "rate-limit override preserves sequence")

KnifeService.OnPlayerDied(player)
assert(remote._lastFire[2].overriddenState == nil or remote._lastFire[2].payloadType == "StateOverride", "death cleanup does not corrupt last response")

__Test.runDelayedTasks()
assert(remote._lastFire[2].payloadType == "CooldownReset", "knife cooldown reset is sent after scheduled reset")
assert(remote._lastFire[2].actionName == "Stab", "knife cooldown reset names the action")

KnifeService.OnPlayerRemoving(player)
spoofer.Parent = nil
__Test.clearDelayedTasks()
__Test.setTick(nil)

print("[KnifeService.test] passed")
return true
