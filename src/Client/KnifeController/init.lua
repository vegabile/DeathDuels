local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DebugUtility = require(ReplicatedStorage.DebugUtility)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)

local Configs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)
local ClientEventBus = require(script.Parent.ClientEventBus)

local DEBUG = Configs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local KnifeController = {}

local localPlayer = Players.LocalPlayer
local stateMachine = KnifeStateMachine.new()
local sequenceId = 0
local knifeEquipped = false
local remote: RemoteEvent? = nil
local remoteConnection: RBXScriptConnection? = nil
local safetyTimeoutThread: thread? = nil

local keybindMap: { [Enum.KeyCode]: string } = {}
for _, bind in Configs.Keybinds do
	if bind.keycode then
		keybindMap[bind.keycode] = bind.mappedAction
	end
end

function KnifeController.onKnifeEquipped()
	knifeEquipped = true
	debugPrint(DEBUG, `[KnifeController] Knife equipped`)

	local remoteName = `KnifeAction_{localPlayer.UserId}`
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(remoteName, 10)
	if not remote then
		warn(`[KnifeController] Could not find remote: {remoteName}`)
		return
	end

	if remoteConnection then
		remoteConnection:Disconnect()
	end
	remoteConnection = remote.OnClientEvent:Connect(function(payload)
		KnifeController._handleServerResponse(payload)
	end)
end

function KnifeController.onKnifeUnequipped()
	knifeEquipped = false
	debugPrint(DEBUG, `[KnifeController] Knife unequipped`)
	--// State persists through unequip/reequip per spec
end

function KnifeController.onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if not knifeEquipped then return end

	local actionName = keybindMap[input.KeyCode]
	if not actionName then return end

	local action = ActionRegistry.getAction(actionName)
	if not action then return end

	local accepted = KnifeStateMachine.setActionActive(stateMachine, actionName)
	if not accepted then
		debugPrint(DEBUG, `[KnifeController] Action blocked by state machine`)
		return
	end

	sequenceId += 1

	local directionVector = nil
	if actionName == "Throw" then
		local camera = workspace.CurrentCamera
		if camera then
			directionVector = camera.CFrame.LookVector
		end
	end

	action.clientExecute(stateMachine, directionVector)

	if remote then
		remote:FireServer({
			desiredAction = actionName,
			directionVector = directionVector,
			sequenceId = sequenceId,
		})
	end

	local thisSequence = sequenceId
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
	end
	safetyTimeoutThread = task.delay(action.cooldown + Configs.SafetyTimeoutBuffer, function()
		if sequenceId == thisSequence then
			KnifeStateMachine.resetAction(stateMachine, actionName)
			debugPrint(DEBUG, `[KnifeController] Safety timeout triggered for {actionName}`)
		end
	end)
end

function KnifeController._handleServerResponse(payload: any)
	if type(payload) ~= "table" then return end

	if payload.payloadType == "CooldownReset" then
		KnifeStateMachine.resetAction(stateMachine, payload.actionName)
		if safetyTimeoutThread then
			task.cancel(safetyTimeoutThread)
			safetyTimeoutThread = nil
		end
		debugPrint(DEBUG, `[KnifeController] Cooldown reset for {payload.actionName}`)

	elseif payload.payloadType == "StateOverride" then
		if payload.sequenceId and payload.sequenceId < sequenceId then
			debugPrint(DEBUG, `[KnifeController] Ignoring stale StateOverride (seq {payload.sequenceId} < {sequenceId})`)
			return
		end
		stateMachine.isStabbing = payload.overriddenState.isStabbing
		stateMachine.isThrowing = payload.overriddenState.isThrowing
		debugPrint(DEBUG, `[KnifeController] State overridden by server`)

	elseif payload.payloadType == "ProjectileHitConfirm" then
		debugPrint(DEBUG, `[KnifeController] Hit confirmed for {payload.actionName}`)
		ClientEventBus:Fire("KnifeHitConfirmed", payload.actionName)
	end
end

function KnifeController.onPlayerDied()
	KnifeStateMachine.resetAll(stateMachine)
	knifeEquipped = false
	if safetyTimeoutThread then
		task.cancel(safetyTimeoutThread)
		safetyTimeoutThread = nil
	end
end

return KnifeController
