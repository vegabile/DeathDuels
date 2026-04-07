local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Round.Types)
type TeleportMetadata = Types.TeleportMetadata

local TeleportMetadataService = {}

local _teams: { [number]: number } = {} -- UserId -> 1|2
local _queueType: number = 0
local _mapName: string = ""
local _timestamp: number = 0
local _initialized = false

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

return TeleportMetadataService
