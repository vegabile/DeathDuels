local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Round.Types)
type TeleportMetadata = Types.TeleportMetadata

local TeleportMetadataService = {}

local _teams: { [number]: number } = {} 
local _queueType: number = 0
local _mapName: string = ""
local _timestamp: number = 0
local _matchId: string = ""
local _placeId: number = 0
local _reservedServerAccessCode: string = ""
local _initialized = false
local _loadouts: { [string]: { knifeName: string?, gunName: string?, Power: string?, powerName: string? } } = {}
local _parties: { [string]: { leaderUserId: number, memberUserIds: { number } } } = {}
local _partyByUserId: { [number]: string } = {}

function TeleportMetadataService.Initialize(metadata: TeleportMetadata)
	if _initialized then return end

	for _, entry in metadata.teamOnePlayers do
		_teams[entry.UserId] = 1
	end
	for _, entry in metadata.teamTwoPlayers do
		_teams[entry.UserId] = 2
	end

	_queueType = metadata.queueType
	_mapName = metadata.mapName
	_timestamp = metadata.timestamp
	_matchId = metadata.matchId
	_placeId = metadata.placeId
	_reservedServerAccessCode = metadata.reservedServerAccessCode
	if metadata.loadouts then
		for userId, loadout in metadata.loadouts do
			_loadouts[tostring(userId)] = loadout
		end
	end
	if metadata.parties then
		for partyId, party in metadata.parties do
			local memberUserIds = {}
			for _, userId in party.memberUserIds do
				table.insert(memberUserIds, userId)
				_partyByUserId[userId] = partyId
			end
			_partyByUserId[party.leaderUserId] = partyId
			_parties[partyId] = {
				leaderUserId = party.leaderUserId,
				memberUserIds = memberUserIds,
			}
		end
	end
	_initialized = true
end

function TeleportMetadataService.SetTeam(userId: number, team: number)
	_teams[userId] = team
end

function TeleportMetadataService.GetTeam(player: Player): number?
	local team = _teams[player.UserId]
	if not team then
		warn(`[TeleportMetadataService] No team for {player.Name} ({player.UserId})`)
	end
	return team
end

function TeleportMetadataService.GetQueueType(): number
	return _queueType
end

function TeleportMetadataService.GetMapName(): string
	return _mapName
end

function TeleportMetadataService.GetTimestamp(): number
	return _timestamp
end

function TeleportMetadataService.GetMatchId(): string
	return _matchId
end

function TeleportMetadataService.GetPlaceId(): number
	return _placeId
end

function TeleportMetadataService.GetReservedServerAccessCode(): string
	return _reservedServerAccessCode
end

function TeleportMetadataService.GetLoadout(userId: number): { knifeName: string?, gunName: string?, Power: string?, powerName: string? }?
	return _loadouts[tostring(userId)]
end

function TeleportMetadataService.SetLoadout(userId: number, loadout: { knifeName: string?, gunName: string?, Power: string?, powerName: string? })
	_loadouts[tostring(userId)] = loadout
end

function TeleportMetadataService.GetPartyIdForUserId(userId: number): string?
	return _partyByUserId[userId]
end

function TeleportMetadataService.GetPartyForUserId(userId: number): { leaderUserId: number, memberUserIds: { number } }?
	local partyId = _partyByUserId[userId]
	if not partyId then return nil end
	return _parties[partyId]
end

function TeleportMetadataService.GetParties(): { [string]: { leaderUserId: number, memberUserIds: { number } } }
	local copy = {}
	for partyId, party in _parties do
		local memberUserIds = {}
		for _, userId in party.memberUserIds do table.insert(memberUserIds, userId) end
		copy[partyId] = {
			leaderUserId = party.leaderUserId,
			memberUserIds = memberUserIds,
		}
	end
	return copy
end

return TeleportMetadataService
