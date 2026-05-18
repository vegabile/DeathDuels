local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local SharedPowerConfigs = require(ReplicatedStorage.Power.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local Configs = require(script.Configs)
local PowerRegistry = require(script.PowerRegistry)
local RoundScope = require(script.RoundScope)
local ServerTypes = require(script.Types)

type Power = ServerTypes.Power
type PowerResult = ServerTypes.PowerResult
type Loadout = ServerTypes.Loadout

local instancesByPlayer: { [Player]: any } = {}
local pendingLoadoutsByPlayer: { [Player]: Loadout? } = {}
local currentRoundState: string = ""

ServerEventBus:Connect("RoundStateChanged", function(newState: string)
	currentRoundState = newState
	if newState ~= RoundConfigs.GAME_STATES.RoundActive then
		RoundScope.Cleanup()
	end
end)

local PowerService = {}
PowerService.__index = PowerService

local function nowUnixMs(): number
	return DateTime.now().UnixTimestampMillis
end

local function secondsToMs(seconds: number): number
	return math.floor((seconds * 1000) + 0.5)
end

local function applyLoadout(self, loadout: Loadout?)
	self._equippedPower = nil
	self.player:SetAttribute("EquippedPower", nil)

	if loadout == nil or type(loadout.Power) ~= "string" then
		warn(`[POWER] Missing loadout.Power for {self.player.Name}`)
		return
	end

	local resolved = self._registry.getPower(loadout.Power:lower())
	if resolved then
		self._equippedPower = resolved
		self.player:SetAttribute("EquippedPower", resolved.name)
	else
		warn(`[POWER] Unresolved power '{loadout.Power}' for {self.player.Name}`)
	end
end

local function normalizeNewArgs(loadoutOrRegistry: any?, registryOverride: any?): (Loadout?, any, boolean)
	if registryOverride ~= nil then
		return loadoutOrRegistry :: Loadout?, registryOverride, true
	end

	if type(loadoutOrRegistry) == "table" and type(loadoutOrRegistry.getPower) == "function" then
		return nil, loadoutOrRegistry, false
	end

	return loadoutOrRegistry :: Loadout?, nil, loadoutOrRegistry ~= nil
end

function PowerService.new(player: Player, loadoutOrRegistry: any?, registryOverride: any?): any
	local loadout, registry, hasExplicitLoadout = normalizeNewArgs(loadoutOrRegistry, registryOverride)

	local self = setmetatable({}, PowerService)
	self.player = player
	self._cooldowns = {}
	self._lastAttempt = {}
	self._registry = registry or PowerRegistry
	self._equippedPower = nil
	player:SetAttribute("EquippedPower", nil)

	local pendingLoadout = pendingLoadoutsByPlayer[player]
	if pendingLoadout ~= nil then
		applyLoadout(self, pendingLoadout)
		pendingLoadoutsByPlayer[player] = nil
	elseif hasExplicitLoadout then
		applyLoadout(self, loadout)
	end

	instancesByPlayer[player] = self
	return self
end

function PowerService.Get(player: Player): any?
	return instancesByPlayer[player]
end

function PowerService.IsPlayerRoundEligible(player: Player): boolean
	return player:GetAttribute(SharedPowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE) == true
end

function PowerService.AssignLoadout(player: Player, loadout: Loadout?)
	local svc = instancesByPlayer[player]
	if svc then
		svc:SetLoadout(loadout)
		return
	end

	pendingLoadoutsByPlayer[player] = loadout
end

function PowerService:SetLoadout(loadout: Loadout?)
	table.clear(self._cooldowns)
	table.clear(self._lastAttempt)
	applyLoadout(self, loadout)
	pendingLoadoutsByPlayer[self.player] = nil
end

function PowerService:Destroy()
	table.clear(self._cooldowns)
	table.clear(self._lastAttempt)
	self.player:SetAttribute("EquippedPower", nil)
	instancesByPlayer[self.player] = nil
	pendingLoadoutsByPlayer[self.player] = nil
end

function PowerService:Activate(powerName: string, payload: any): PowerResult
	local now = nowUnixMs()

	if type(powerName) ~= "string" then
		return { success = false, reason = Reasons.UnknownPower }
	end
	local requested = self._registry.getPower(powerName:lower())
	if not requested then
		return { success = false, reason = Reasons.UnknownPower }
	end

	if self._equippedPower == nil or self._equippedPower.name ~= requested.name then
		return { success = false, reason = Reasons.NoPermission }
	end

	if not self.player:IsDescendantOf(Players) then
		return { success = false, reason = Reasons.InvalidState }
	end
	if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
		return { success = false, reason = Reasons.InvalidState }
	end
	if not PowerService.IsPlayerRoundEligible(self.player) then
		return { success = false, reason = Reasons.InvalidState }
	end
	local char = self.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return { success = false, reason = Reasons.InvalidState }
	end

	local lastAttempt = self._lastAttempt[requested.name] or 0
	if (now - lastAttempt) < secondsToMs(Configs.DEBOUNCE) then
		self._lastAttempt[requested.name] = now
		return { success = false, reason = Reasons.Debounced }
	end

	local ok, reason = requested.validatePayload(payload)
	if not ok then
		self._lastAttempt[requested.name] = now
		return { success = false, reason = reason or Reasons.InvalidTarget }
	end

	local expiry = self._cooldowns[requested.name] or 0
	if now < expiry then
		self._lastAttempt[requested.name] = now
		return {
			success = false,
			reason = Reasons.OnCooldown,
			cooldownEndsAtUnixMs = expiry,
			serverNowUnixMs = now,
		}
	end

	local cooldownEndsAtUnixMs = now + secondsToMs(requested.cooldown)
	self._cooldowns[requested.name] = cooldownEndsAtUnixMs
	self._lastAttempt[requested.name] = now

	requested:Execute(self.player, payload)

	return {
		success = true,
		reason = nil,
		cooldownEndsAtUnixMs = cooldownEndsAtUnixMs,
		serverNowUnixMs = now,
	}
end

function PowerService._reset()
	for _, svc in instancesByPlayer do
		table.clear(svc._cooldowns)
		table.clear(svc._lastAttempt)
	end
	table.clear(instancesByPlayer)
	table.clear(pendingLoadoutsByPlayer)
	RoundScope.Cleanup()
	currentRoundState = ""
end

return PowerService
