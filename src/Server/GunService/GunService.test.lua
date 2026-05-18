local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local GunService = require(script.Parent)

__Test.clearDelayedTasks()
__Test.setTick(1000)

local function makePlayer(userId, withGun)
	local player = Instance.new("Player")
	player.Name = `GunTester{userId}`
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
	if withGun then
		local tool = Instance.new("Tool")
		tool.Name = "TestGun"
		tool:SetAttribute("IsGun", true)
		tool.Parent = character
	end
	player.Character = character

	return player
end

local function validShoot(sequenceId)
	return {
		desiredAction = "Shoot",
		sequenceId = sequenceId,
		directionVector = Vector3.new(1, 0, 0),
		restOrigin = Vector3.new(0, 0, 0),
	}
end

local player = makePlayer(6101, true)
GunService.OnPlayerAdded(player)
local remote = NetworkRouter:Get(GunService._getRemoteName(player))

local spoofer = makePlayer(6102, true)
remote.OnServerEvent:Fire(spoofer, validShoot(1))
assert(remote._lastFire == nil, "spoofed gun remote does not send a response on the victim remote")

ServerEventBus:FireSticky("RoundStateChanged", RoundConfigs.GAME_STATES.WaitingForPlayers)
GunService._handleActionRequest(player, validShoot(2))
assert(remote._lastFire[2].payloadType == "StateOverride", "gun action outside active round is rejected")
assert(remote._lastFire[2].sequenceId == 2, "state override preserves sanitized sequence id")

ServerEventBus:FireSticky("RoundStateChanged", RoundConfigs.GAME_STATES.RoundActive)
player:SetAttribute("CombatDisabled", true)
GunService._handleActionRequest(player, validShoot(3))
assert(remote._lastFire[2].payloadType == "StateOverride", "CombatDisabled rejects gun action")
player:SetAttribute("CombatDisabled", nil)

GunService._handleActionRequest(player, { desiredAction = "Shoot", sequenceId = math.huge })
assert(remote._lastFire[2].payloadType == "StateOverride", "malformed gun payload is rejected")
assert(remote._lastFire[2].sequenceId == 0, "malformed gun payload is sanitized to sequence zero")

player:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, nil)
GunService._handleActionRequest(player, validShoot(4))
assert(remote._lastFire[2].payloadType == "StateOverride", "combat-ineligible gun action is rejected")
assert(remote._lastFire[2].sequenceId == 4, "combat-ineligible override preserves sequence")

player:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, false)
GunService._handleActionRequest(player, validShoot(5))
assert(remote._lastFire[2].payloadType == "StateOverride", "false combat eligibility rejects gun action")
assert(remote._lastFire[2].sequenceId == 5, "false combat eligibility override preserves sequence")

player:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, true)
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
humanoid.Health = 0
GunService._handleActionRequest(player, validShoot(6))
assert(remote._lastFire[2].payloadType == "StateOverride", "dead humanoid rejects gun action")
assert(remote._lastFire[2].sequenceId == 6, "dead humanoid override preserves sequence")
humanoid.Health = 100

local noGunPlayer = makePlayer(6103, false)
GunService.OnPlayerAdded(noGunPlayer)
local noGunRemote = NetworkRouter:Get(GunService._getRemoteName(noGunPlayer))
noGunPlayer:SetAttribute(RoundConfigs.COMBAT_ELIGIBLE_ATTRIBUTE, true)
GunService._handleActionRequest(noGunPlayer, validShoot(7))
assert(noGunRemote._lastFire[2].payloadType == "StateOverride", "player without gun is rejected")
GunService.OnPlayerRemoving(noGunPlayer)

remote._lastFire = nil
GunService._handleActionRequest(player, validShoot(8))
assert(remote._lastFire == nil, "accepted gun action does not send immediate state override")
__Test.setTick(1000.1)
GunService._handleActionRequest(player, validShoot(9))
assert(remote._lastFire[2].payloadType == "StateOverride", "rapid gun repeat is rate-limited")
assert(remote._lastFire[2].sequenceId == 9, "rate-limit override preserves sequence")

__Test.runDelayedTasks()
assert(remote._lastFire[2].payloadType == "CooldownReset", "gun cooldown reset is sent after scheduled reset")
assert(remote._lastFire[2].actionName == "Shoot", "gun cooldown reset names the action")

GunService.OnPlayerRemoving(player)
spoofer.Parent = nil
__Test.clearDelayedTasks()
__Test.setTick(nil)

print("[GunService.test] passed")
return true
