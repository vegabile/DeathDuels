



local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local derive = require(ReplicatedStorage.Spectate.derive)
local Types = require(ReplicatedStorage.Spectate.Types)

export type SpectateClientState = Types.SpectateClientState

local SpectateController = {}

local initialized = false
local camera: Camera? = nil
local localPlayer: Player? = nil
local state: SpectateClientState = {
	isRoundActive = false,
	selfInGame = false,
	selfEliminated = false,
	players = {},
	canSpectate = false,
	availableTargets = {},
	currentTargetUserId = nil,
	isSpectating = false,
}

local function getLocalHumanoid(): Humanoid?
	if not localPlayer then return nil end
	local char = localPlayer.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function restoreCameraToSelf()
	if not camera then return end
	camera.CameraSubject = getLocalHumanoid()  
end

local function applyCamera()
	if not camera then return end
	if not state.isSpectating or state.currentTargetUserId == nil then
		restoreCameraToSelf()
		return
	end

	local target = Players:GetPlayerByUserId(state.currentTargetUserId)
	if not target then
		warn(`[Spectate] target userId {state.currentTargetUserId} resolves to no Player; clearing`)
		state.currentTargetUserId = nil
		state.isSpectating = false
		restoreCameraToSelf()
		return
	end

	local char = target.Character
	if not char then
		warn(`[Spectate] target {target.Name} has no Character yet; clearing`)
		state.currentTargetUserId = nil
		state.isSpectating = false
		restoreCameraToSelf()
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[Spectate] target {target.Name} has no Humanoid; clearing`)
		state.currentTargetUserId = nil
		state.isSpectating = false
		restoreCameraToSelf()
		return
	end

	camera.CameraSubject = humanoid
end

function SpectateController.Init(injectedCamera: Camera?, injectedLocalPlayer: Player?)
	if initialized then
		warn("[Spectate] Init called twice; ignoring")
		return
	end
	initialized = true
	camera = injectedCamera
	localPlayer = injectedLocalPlayer or Players.LocalPlayer
end

function SpectateController.HandleRoundUpdate(snapshot: any)
	if not localPlayer then
		warn("[Spectate] HandleRoundUpdate called before Init")
		return
	end
	state = derive(snapshot, localPlayer.UserId, state.currentTargetUserId)
	applyCamera()
end

function SpectateController.GetState(): SpectateClientState
	return state
end

function SpectateController.SelectTarget(userId: number)
	if not state.canSpectate then
		warn("[Spectate] SelectTarget called while canSpectate=false; ignoring")
		return
	end
	if not table.find(state.availableTargets, userId) then
		warn(`[Spectate] SelectTarget({userId}): userId not in availableTargets; ignoring`)
		return
	end
	state.currentTargetUserId = userId
	state.isSpectating = true
	applyCamera()
end

local function cycle(delta: number)
	if not state.canSpectate then
		warn("[Spectate] cycle called while canSpectate=false; ignoring")
		return
	end
	local list = state.availableTargets
	if #list == 0 then
		warn("[Spectate] cycle called with no availableTargets; ignoring")
		return
	end
	if state.currentTargetUserId == nil then
		
		state.currentTargetUserId = if delta > 0 then list[1] else list[#list]
	else
		local currentIdx = table.find(list, state.currentTargetUserId) or 1
		local nextIdx = ((currentIdx - 1 + delta) % #list) + 1
		state.currentTargetUserId = list[nextIdx]
	end
	state.isSpectating = true
	applyCamera()
end

function SpectateController.SelectNext()
	cycle(1)
end

function SpectateController.SelectPrevious()
	cycle(-1)
end

function SpectateController.Clear()
	state.currentTargetUserId = nil
	state.isSpectating = false
	restoreCameraToSelf()
end

return SpectateController
