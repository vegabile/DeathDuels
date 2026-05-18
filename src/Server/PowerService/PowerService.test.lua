local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PowerReasons = require(ReplicatedStorage.Power.PowerFailReason)
local PowerConfigs = require(ReplicatedStorage.Power.Configs)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local PowerService = require(script.Parent)

PowerService._reset()
__Test.clearDelayedTasks()
__Test.setNowMs(100000)

local executeCount = 0
local fakePower = {
	name = "blink",
	cooldown = 2,
	validatePayload = function(payload)
		if type(payload) == "table" and payload.ok == true then
			return true, nil
		end
		return false, PowerReasons.InvalidTarget
	end,
	Execute = function(_, player, payload)
		executeCount += 1
		player:SetAttribute("LastPowerPayload", payload.marker)
	end,
}

local otherPower = {
	name = "other",
	cooldown = 1,
	validatePayload = function()
		return true, nil
	end,
	Execute = function() end,
}

local registry = {
	getPower = function(name)
		if name == "blink" then
			return fakePower
		elseif name == "other" then
			return otherPower
		end
		return nil
	end,
}

local player = Instance.new("Player")
player.Name = "PowerUser"
player.UserId = 77
player.Parent = Players
local character = Instance.new("Model")
character.Name = "Character"
local humanoid = Instance.new("Humanoid")
humanoid.Name = "Humanoid"
humanoid.Parent = character
player.Character = character
player:SetAttribute(PowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE, true)

ServerEventBus:FireSticky("RoundStateChanged", RoundConfigs.GAME_STATES.RoundActive)
local service = PowerService.new(player, { Power = "Blink" }, registry)
assert(PowerService.Get(player) == service, "PowerService.Get returns active service")
assert(player:GetAttribute("EquippedPower") == "blink", "loadout equips lower-cased power")

local result = service:Activate("missing", { ok = true })
assert(result.success == false and result.reason == PowerReasons.UnknownPower, "unknown power is rejected")

result = service:Activate("other", { ok = true })
assert(result.success == false and result.reason == PowerReasons.NoPermission, "non-equipped power is rejected")

player:SetAttribute(PowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE, false)
result = service:Activate("blink", { ok = true })
assert(result.success == false and result.reason == PowerReasons.InvalidState, "round-ineligible player is rejected")
player:SetAttribute(PowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE, true)

result = service:Activate("blink", { ok = false })
assert(result.success == false and result.reason == PowerReasons.InvalidTarget, "power payload validation failure is returned")

humanoid.Health = 0 / 0
result = service:Activate("blink", { ok = true })
assert(result.success == false and result.reason == PowerReasons.InvalidState, "NaN humanoid health is rejected")
humanoid.Health = math.huge
result = service:Activate("blink", { ok = true })
assert(result.success == false and result.reason == PowerReasons.InvalidState, "infinite humanoid health is rejected")
humanoid.Health = 100

__Test.setNowMs(100100)
result = service:Activate("blink", { ok = true, marker = "accepted" })
assert(result.success == true, "valid activation succeeds")
assert(executeCount == 1, "power executes once")
assert(player:GetAttribute("LastPowerPayload") == "accepted", "power receives payload")
assert(result.cooldownEndsAtUnixMs == 102100, "cooldown end is calculated from server time")

__Test.setNowMs(100120)
result = service:Activate("blink", { ok = true })
assert(result.success == false and result.reason == PowerReasons.Debounced, "rapid repeat is debounced")

__Test.setNowMs(100300)
result = service:Activate("blink", { ok = true })
assert(result.success == false and result.reason == PowerReasons.OnCooldown, "post-debounce repeat is on cooldown")
assert(result.cooldownEndsAtUnixMs == 102100, "cooldown response includes original expiry")

PowerService.AssignLoadout(player, { Power = "Other" })
assert(player:GetAttribute("EquippedPower") == "other", "AssignLoadout updates existing service")

service:Destroy()
assert(PowerService.Get(player) == nil, "Destroy removes active service")
assert(player:GetAttribute("EquippedPower") == nil, "Destroy clears equipped attribute")

__Test.clearDelayedTasks()
__Test.setNowMs(nil)
PowerService._reset()

print("[PowerService.PowerService.test] passed")
return true
