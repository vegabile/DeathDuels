--// Only files under src/Server/RoundService/ may require this module.
--// This is a dumb store: it writes facts, answers questions about records,
--// and fires ChangedSignal. It does NOT decide what is "ready" — that is
--// exclusively the RoundOrchestrator's job.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = require(ReplicatedStorage.Round.Configs)

export type ReadinessRecord = {
	player: any,
	facts: { [string]: boolean },
	loadAttempt: number,
	createdAt: number,
}

local PlayerReadiness = {}

local records: { [any]: ReadinessRecord } = {}
local ChangedSignal: BindableEvent = Instance.new("BindableEvent")
PlayerReadiness.ChangedSignal = ChangedSignal

local function isRequiredFact(factName: string): boolean
	for _, name in Configs.REQUIRED_FACTS do
		if name == factName then return true end
	end
	return false
end

function PlayerReadiness.ensureRecord(player: any): ReadinessRecord
	local existing = records[player]
	if existing then return existing end
	local rec: ReadinessRecord = {
		player = player,
		facts = {},
		loadAttempt = 0,
		createdAt = os.clock(),
	}
	records[player] = rec
	return rec
end

function PlayerReadiness.destroyRecord(player: any)
	records[player] = nil
end

function PlayerReadiness.getRecord(player: any): ReadinessRecord?
	return records[player]
end

function PlayerReadiness.recordFact(player: any, factName: string)
	if not isRequiredFact(factName) then
		warn(`[PlayerReadiness] unknown fact "{factName}"; ignored`)
		return
	end
	local rec = records[player] or PlayerReadiness.ensureRecord(player)
	if rec.facts[factName] then return end
	rec.facts[factName] = true
	ChangedSignal:Fire()
end

function PlayerReadiness.clearFact(player: any, factName: string)
	local rec = records[player]
	if not rec then return end
	if not rec.facts[factName] then return end
	rec.facts[factName] = nil
	ChangedSignal:Fire()
end

function PlayerReadiness.isComplete(player: Player): boolean
	local rec = records[player]
	if not rec then return false end
	if not (player.Character and player.Character.PrimaryPart) then return false end --// FLAG: Refactor this into the existing pattern
	for _, name in Configs.REQUIRED_FACTS do
		if not rec.facts[name] then return false end
	end

	return true
end

function PlayerReadiness.missingFacts(player: Player): { string }
	local missing = {}
	local rec = records[player]
	for _, name in Configs.REQUIRED_FACTS do
		if not rec or not rec.facts[name] then
			table.insert(missing, name)
		end
	end
	return missing
end

function PlayerReadiness.beginCharacterLoad(player: any): number
	local rec = records[player] or PlayerReadiness.ensureRecord(player)
	rec.loadAttempt += 1
	rec.facts.CharacterLoaded = nil
	rec.facts.CharacterUsable = nil
	--// Always fire once — token advance is a meaningful change even without fact clears.
	ChangedSignal:Fire()
	return rec.loadAttempt
end

function PlayerReadiness.recordCharacterFact(player: any, token: number, factName: string)
	if factName ~= "CharacterLoaded" and factName ~= "CharacterUsable" then
		warn(`[PlayerReadiness] recordCharacterFact: "{factName}" is not a character fact`)
		return
	end
	local rec = records[player]
	if not rec then
		warn(`[PlayerReadiness] recordCharacterFact: no record for {tostring(player)}`)
		return
	end
	if token ~= rec.loadAttempt then
		local playerName = (player :: any).Name or tostring(player)
		warn(`[PlayerReadiness] stale char fact {factName} for {playerName} (token {token} != current {rec.loadAttempt})`)
		return
	end
	if rec.facts[factName] then return end
	rec.facts[factName] = true
	ChangedSignal:Fire()
end

function PlayerReadiness.waitForChange(timeout: number)
	local fired = false
	local conn
	conn = ChangedSignal.Event:Connect(function()
		fired = true
	end)
	local timer = task.delay(timeout, function()
		fired = true
	end)
	while not fired do
		task.wait()
	end
	conn:Disconnect()
	task.cancel(timer)
end

function PlayerReadiness.waitForComplete(player: any, timeout: number): boolean
	if PlayerReadiness.isComplete(player) then return true end
	local deadline = os.clock() + timeout
	while true do
		local timeLeft = deadline - os.clock()
		if timeLeft <= 0 then return false end
		PlayerReadiness.waitForChange(timeLeft)
		if PlayerReadiness.isComplete(player) then return true end
	end
end

--// Test-only: clears all records and resets the store.
function PlayerReadiness._reset()
	records = {}
end

return PlayerReadiness
