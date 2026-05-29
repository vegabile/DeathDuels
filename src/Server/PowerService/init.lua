local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local Configs = require(script.Configs)
local PowerRegistry = require(script.PowerRegistry)
local ServerTypes = require(script.Types)

type Power = ServerTypes.Power
type PowerResult = ServerTypes.PowerResult
type Loadout = ServerTypes.Loadout

--// ─── Module state ────────────────────────────────────────────────────────

local instancesByPlayer: { [Player]: any } = {}
local currentRoundState: string = ""

ServerEventBus:Connect("RoundStateChanged", function(newState: string)
	currentRoundState = newState
end)

--// ─── Class ───────────────────────────────────────────────────────────────

local PowerService = {}
PowerService.__index = PowerService

function PowerService.new(player: Player, loadout: Loadout?, registry: any?): any
	local self = setmetatable({}, PowerService)
	self.player = player
	self._cooldowns = {}
	self._lastAttempt = {}
	self._registry = registry or PowerRegistry
	self._equippedPower = nil

	if loadout == nil or type(loadout.Power) ~= "string" then
		warn(`[POWER] Missing loadout.Power for {player.Name}`)
	else
		local resolved = self._registry.getPower(loadout.Power:lower())
		if resolved then
			self._equippedPower = resolved
		else
			warn(`[POWER] Unresolved power '{loadout.Power}' for {player.Name}`)
		end
	end

	instancesByPlayer[player] = self
	return self
end

function PowerService.Get(player: Player): any?
	return instancesByPlayer[player]
end

function PowerService:Destroy()
	table.clear(self._cooldowns)
	table.clear(self._lastAttempt)
	instancesByPlayer[self.player] = nil
end

function PowerService:Activate(powerName: string, payload: any): PowerResult
	local now = tick()

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
	local char = self.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return { success = false, reason = Reasons.InvalidState }
	end

	local lastAttempt = self._lastAttempt[requested.name] or 0
	if (now - lastAttempt) < Configs.DEBOUNCE then
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
		return { success = false, reason = Reasons.OnCooldown }
	end

	self._lastAttempt[requested.name] = now

	local ok, applied = pcall(function()
		return requested:Execute(self.player, payload)
	end)
	if not ok then
		warn(`[POWER] Execute threw for '{requested.name}': {applied}`)
		return { success = false, reason = Reasons.InvalidState }
	end
	if applied ~= true then
		return { success = false, reason = Reasons.InvalidState }
	end

	self._cooldowns[requested.name] = now + requested.cooldown

	return { success = true, reason = nil }
end

--// ─── Test hooks ──────────────────────────────────────────────────────────
--// Called only by integration_power_system.test.lua.

function PowerService._reset()
	for _, svc in instancesByPlayer do
		table.clear(svc._cooldowns)
		table.clear(svc._lastAttempt)
	end
	table.clear(instancesByPlayer)
	currentRoundState = ""
end

return PowerService
