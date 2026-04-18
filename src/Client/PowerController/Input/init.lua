local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientEventBus = require(script.Parent.Parent.ClientEventBus)
local InputRouter = require(script.Parent.Parent.InputRouter)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local SharedPowerConfigs = require(ReplicatedStorage.Power.Configs)

local Configs = require(script.Configs)

local Input = {}

local localPlayer = Players.LocalPlayer

local state = {
	abilityUi        = nil :: ScreenGui?,
	button           = nil :: TextButton?,
	powerName        = nil :: string?,
	powerEntry       = nil :: { displayName: string, cooldown: number }?,
	roundActive      = false,
	alive            = false,
	pendingResponse  = false,
	pendingTimeout   = nil :: thread?,
	cooldownUntil    = 0,
	cooldownThread   = nil :: thread?,
	sequenceId       = 0,
	connections      = {} :: { RBXScriptConnection | { Disconnect: (any) -> () } },
	humanoidDied     = nil :: RBXScriptConnection?,
	remoteConnection = nil :: RBXScriptConnection?,
	remoteName       = "",
	bound            = false,
	initialized      = false,
}

local function remoteName(): string
	return `PowerAction_{localPlayer.UserId}`
end

local function isOnCooldown(): boolean
	return os.clock() < state.cooldownUntil
end

local function isActivatable(): boolean
	return state.powerEntry ~= nil
		and state.roundActive
		and state.alive
		and not state.pendingResponse
		and not isOnCooldown()
end

local function updateButtonText()
	if not state.button or not state.powerEntry then return end
	local remaining = state.cooldownUntil - os.clock()
	if state.pendingResponse or remaining > 0 then
		state.button.AutoButtonColor = false
		state.button.Active = false
		local label = state.pendingResponse
			and state.powerEntry.displayName
			or string.format("%.1fs", remaining)
		state.button.Text = label
		state.button.TextTransparency = 0.4
	else
		state.button.AutoButtonColor = true
		state.button.Active = true
		state.button.Text = state.powerEntry.displayName
		state.button.TextTransparency = 0
	end
end

local function startCooldownThread()
	if state.cooldownThread then
		task.cancel(state.cooldownThread)
		state.cooldownThread = nil
	end
	state.cooldownThread = task.spawn(function()
		while os.clock() < state.cooldownUntil do
			updateButtonText()
			task.wait(Configs.COOLDOWN_UPDATE_INTERVAL)
		end
		state.cooldownThread = nil
		updateButtonText()
	end)
end

local function cancelCooldown()
	if state.cooldownThread then
		task.cancel(state.cooldownThread)
		state.cooldownThread = nil
	end
	if state.pendingTimeout then
		task.cancel(state.pendingTimeout)
		state.pendingTimeout = nil
	end
	state.cooldownUntil = 0
	state.pendingResponse = false
	updateButtonText()
end

local onActivatePressed

local function refresh()
	if not state.abilityUi then return end
	local visible = state.powerEntry ~= nil
		and state.roundActive
		and state.alive
	state.abilityUi.Enabled = visible

	if visible then
		if not state.bound then
			InputRouter.bindPower(onActivatePressed)
			state.bound = true
		end
		updateButtonText()
	else
		if state.bound then
			InputRouter.unbindPower()
			state.bound = false
		end
		cancelCooldown()
	end
end

onActivatePressed = function()
	if not isActivatable() then return end
	if not state.powerName or not state.powerEntry then return end

	state.sequenceId += 1
	state.pendingResponse = true
	updateButtonText()

	--// Safety timeout: if the server response never arrives, ungrey.
	if state.pendingTimeout then task.cancel(state.pendingTimeout) end
	local thisSequence = state.sequenceId
	state.pendingTimeout = task.delay(
		state.powerEntry.cooldown + Configs.PENDING_TIMEOUT_BUFFER,
		function()
			if state.sequenceId == thisSequence and state.pendingResponse then
				warn(`[POWER] No ActivateResponse for seq={thisSequence}; ungreying`)
				state.pendingResponse = false
				state.pendingTimeout = nil
				updateButtonText()
			end
		end
	)

	NetworkRouter:Call(remoteName(), {
		powerName  = state.powerName,
		payload    = {},
		sequenceId = state.sequenceId,
	})
end

local function onServerResponse(payload: any)
	if type(payload) ~= "table" then return end
	if type(payload.sequenceId) ~= "number" then return end
	if payload.sequenceId ~= state.sequenceId then return end

	state.pendingResponse = false
	if state.pendingTimeout then
		task.cancel(state.pendingTimeout)
		state.pendingTimeout = nil
	end

	local result = payload.result
	if type(result) ~= "table" or result.success ~= true then
		updateButtonText()
		return
	end

	if not state.powerEntry then
		updateButtonText()
		return
	end

	state.cooldownUntil = os.clock() + state.powerEntry.cooldown
	startCooldownThread()
end

local function resolvePower()
	local attr = localPlayer:GetAttribute("EquippedPower")
	if attr == nil then
		state.powerName = nil
		state.powerEntry = nil
		return
	end
	if type(attr) ~= "string" then
		warn(`[POWER] EquippedPower attribute not a string: {typeof(attr)}`)
		state.powerName = nil
		state.powerEntry = nil
		return
	end
	local entry = SharedPowerConfigs.POWERS_BY_NAME[attr]
	if not entry then
		warn(`[POWER] Unknown EquippedPower: {attr}`)
		state.powerName = nil
		state.powerEntry = nil
		return
	end
	state.powerName = attr
	state.powerEntry = entry
end

local function onCharacterAdded(character: Model)
	if state.humanoidDied then
		state.humanoidDied:Disconnect()
		state.humanoidDied = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn(`[POWER] Humanoid never appeared on {character.Name}`)
		return
	end
	state.alive = humanoid.Health > 0
	state.humanoidDied = humanoid.Died:Connect(function()
		state.alive = false
		cancelCooldown()
		refresh()
	end)
	refresh()
end

function Input.init(abilityUi: ScreenGui, button: TextButton)
	if state.initialized then return end
	state.initialized = true

	state.abilityUi = abilityUi
	state.button = button
	state.remoteName = remoteName()

	abilityUi.Enabled = false

	resolvePower()

	local currentChar = localPlayer.Character
	local currentHum = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
	state.alive = currentHum ~= nil and currentHum.Health > 0

	table.insert(state.connections, localPlayer:GetAttributeChangedSignal("EquippedPower"):Connect(function()
		cancelCooldown()
		resolvePower()
		refresh()
	end))

	table.insert(state.connections, ClientEventBus:Connect("RoundUpdate", function(snapshot)
		if type(snapshot) ~= "table" then return end
		local newState = snapshot.state
		local active = newState == RoundConfigs.GAME_STATES.RoundActive
		if active ~= state.roundActive then
			state.roundActive = active
			if not active then cancelCooldown() end
			refresh()
		end
	end))

	table.insert(state.connections, localPlayer.CharacterAdded:Connect(onCharacterAdded))
	if currentChar then onCharacterAdded(currentChar) end

	table.insert(state.connections, button.MouseButton1Click:Connect(onActivatePressed))

	state.remoteConnection = NetworkRouter:Listen(state.remoteName, onServerResponse)

	refresh()
end

function Input.destroy()
	if not state.initialized then return end
	state.initialized = false

	if state.bound then
		InputRouter.unbindPower()
		state.bound = false
	end
	cancelCooldown()
	for _, c in state.connections do c:Disconnect() end
	table.clear(state.connections)
	if state.humanoidDied then state.humanoidDied:Disconnect() state.humanoidDied = nil end
	if state.remoteConnection then state.remoteConnection:Disconnect() state.remoteConnection = nil end

	state.abilityUi = nil
	state.button = nil
	state.powerName = nil
	state.powerEntry = nil
	state.roundActive = false
	state.alive = false
	state.sequenceId = 0
	state.cooldownUntil = 0
end

return Input
