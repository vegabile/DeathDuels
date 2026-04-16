--// src/Shared/Spectate/derive.lua
--// Pure derivation from RoundUpdate snapshot to SpectateClientState.
--// No callbacks, no signals, no Roblox API calls beyond `warn`.

local Types = require(script.Parent.Types)
export type SpectateClientState = Types.SpectateClientState

local ROUND_ACTIVE = "RoundActive"
local STATUS_DEAD = "Dead"

local function emptyState(): SpectateClientState
	return {
		isRoundActive = false,
		selfInGame = false,
		selfEliminated = false,
		players = {},
		canSpectate = false,
		availableTargets = {},
		currentTargetUserId = nil,
		isSpectating = false,
	}
end

local function validateEntry(entry: any): boolean
	if type(entry) ~= "table" then return false end
	if type(entry.player) ~= "table" then return false end
	if type(entry.player.UserId) ~= "number" then return false end
	if type(entry.team) ~= "number" then return false end
	if type(entry.status) ~= "string" then return false end
	if type(entry.isInGame) ~= "boolean" then return false end
	return true
end

local function validateSnapshot(snapshot: any): boolean
	if type(snapshot) ~= "table" then
		warn("[Spectate.derive] snapshot is not a table")
		return false
	end
	if type(snapshot.state) ~= "string" then
		warn("[Spectate.derive] snapshot.state missing or not a string")
		return false
	end
	if type(snapshot.playerStates) ~= "table" then
		warn("[Spectate.derive] snapshot.playerStates missing or not a table")
		return false
	end
	for i, entry in snapshot.playerStates do
		if not validateEntry(entry) then
			warn(`[Spectate.derive] snapshot.playerStates[{i}] failed shape validation`)
			return false
		end
	end
	return true
end

local function derive(snapshot: any, localUserId: number, prevTargetUserId: number?): SpectateClientState
	if not validateSnapshot(snapshot) then
		return emptyState()
	end

	local isRoundActive = snapshot.state == ROUND_ACTIVE

	local players: { [number]: Types.PlayerEntry } = {}
	for _, entry in snapshot.playerStates do
		players[entry.player.UserId] = {
			team = entry.team,
			isInGame = entry.isInGame,
			isEliminated = entry.status == STATUS_DEAD,
		}
	end

	local selfEntry = players[localUserId]
	if selfEntry == nil then
		warn(`[Spectate.derive] local user {localUserId} absent from snapshot; failing closed`)
		local s = emptyState()
		s.isRoundActive = isRoundActive
		s.players = players
		return s
	end

	local selfInGame = selfEntry.isInGame
	local selfEliminated = selfEntry.isEliminated
	local selfTeam = selfEntry.team
	local canSpectate = isRoundActive and (selfEliminated or not selfInGame)

	--// Build availableTargets: teammates asc, then opponents asc.
	local teammates: { number } = {}
	local opponents: { number } = {}
	for userId, p in players do
		if userId == localUserId then continue end
		if not (p.isInGame and not p.isEliminated) then continue end
		if p.team == selfTeam then
			table.insert(teammates, userId)
		else
			table.insert(opponents, userId)
		end
	end
	table.sort(teammates)
	table.sort(opponents)

	local availableTargets: { number } = {}
	for _, id in teammates do table.insert(availableTargets, id) end
	for _, id in opponents do table.insert(availableTargets, id) end

	--// Target resolution.
	local currentTargetUserId: number? = nil
	if prevTargetUserId ~= nil and table.find(availableTargets, prevTargetUserId) then
		currentTargetUserId = prevTargetUserId
	elseif #availableTargets > 0 then
		currentTargetUserId = availableTargets[1]
	end

	if not canSpectate then
		currentTargetUserId = nil
	end

	local isSpectating = canSpectate and currentTargetUserId ~= nil

	return {
		isRoundActive = isRoundActive,
		selfInGame = selfInGame,
		selfEliminated = selfEliminated,
		players = players,
		canSpectate = canSpectate,
		availableTargets = availableTargets,
		currentTargetUserId = currentTargetUserId,
		isSpectating = isSpectating,
	}
end

return derive
