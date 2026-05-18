local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = require(ReplicatedStorage.NetworkRouter)
local Reasons = require(ReplicatedStorage.Power.PowerFailReason)
local RoundConfigs = require(ReplicatedStorage.Round.Configs)
local SharedPowerConfigs = require(ReplicatedStorage.Power.Configs)

local ClientEventBus = require(script.Parent.Parent.ClientEventBus)
local InputRouter = require(script.Parent.Parent.InputRouter)
local Configs = require(script.Configs)

local Input = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local abilityUi: ScreenGui? = nil
local button: TextButton? = nil
local roundConnection: { Disconnect: () -> () }? = nil
local powerAttrConnection: RBXScriptConnection? = nil
local roundEligibleConnection: RBXScriptConnection? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local diedConnection: RBXScriptConnection? = nil
local buttonConnection: RBXScriptConnection? = nil
local responseConnection: RBXScriptConnection? = nil
local cooldownThread: thread? = nil
local pendingTimeoutThread: thread? = nil
local powerBound = false

local state = {
	powerName = nil :: string?,
	powerEntry = nil :: { displayName: string, cooldown: number }?,
	roundActive = false,
	roundEligible = false,
	alive = false,
	pendingResponse = false,
	sequenceId = 0,
	cooldownUntil = 0,
}

local function remoteName(): string
	return `PowerAction_{localPlayer.UserId}`
end

local function cancelCooldownThread()
	if cooldownThread then
		task.cancel(cooldownThread)
		cooldownThread = nil
	end
end

local function cancelPendingTimeout()
	if pendingTimeoutThread then
		task.cancel(pendingTimeoutThread)
		pendingTimeoutThread = nil
	end
end

local function isVisible(): boolean
	return state.powerEntry ~= nil and state.roundActive and state.roundEligible and state.alive
end

local function updateButtonText()
	if not button then
		return
	end

	local powerEntry = state.powerEntry
	if not powerEntry then
		button.Text = "No Power"
		button.Active = false
		button.AutoButtonColor = false
		button.TextTransparency = 0.4
		return
	end

	local remaining = state.cooldownUntil - os.clock()
	local visible = isVisible()
	local enabled = visible and not state.pendingResponse and remaining <= 0

	button.Active = enabled
	button.AutoButtonColor = enabled

	if state.pendingResponse then
		button.Text = powerEntry.displayName
		button.TextTransparency = 0.4
	elseif remaining > 0 then
		button.Text = string.format("%.1fs", remaining)
		button.TextTransparency = 0.4
	else
		button.Text = powerEntry.displayName
		button.TextTransparency = 0
	end
end

local function cancelPendingResponse()
	cancelPendingTimeout()
	state.pendingResponse = false
	updateButtonText()
end

local function clearCooldown()
	cancelCooldownThread()
	state.cooldownUntil = 0
	updateButtonText()
end

local function resetActivationState()
	cancelPendingResponse()
	clearCooldown()
end

local function refreshBinding()
	local visible = isVisible()

	if abilityUi then
		abilityUi.Enabled = visible
	end

	if visible then
		InputRouter.bindPower(function()
			if not state.powerEntry then
				return
			end

			if state.pendingResponse then
				return
			end

			if not state.roundActive or not state.roundEligible or not state.alive then
				return
			end

			if os.clock() < state.cooldownUntil then
				return
			end

			state.sequenceId += 1
			state.pendingResponse = true
			updateButtonText()

			cancelPendingTimeout()
			local thisSequence = state.sequenceId
			local cooldown = state.powerEntry.cooldown
			pendingTimeoutThread = task.delay(cooldown + Configs.PENDING_TIMEOUT_BUFFER, function()
				if state.sequenceId == thisSequence and state.pendingResponse then
					warn(`[POWER] No ActivateResponse for seq={thisSequence}; ungreying button`)
					state.pendingResponse = false
					updateButtonText()
				end
			end)

			NetworkRouter:Call(remoteName(), {
				powerName = state.powerName,
				payload = {},
				sequenceId = thisSequence,
			})
		end)
		powerBound = true
	else
		if powerBound then
			InputRouter.unbindPower()
			powerBound = false
		end
		cancelPendingResponse()
	end

	updateButtonText()
end

local function startCooldown()
	cancelCooldownThread()
	cooldownThread = task.spawn(function()
		while os.clock() < state.cooldownUntil do
			updateButtonText()
			task.wait(Configs.COOLDOWN_UPDATE_INTERVAL)
		end

		state.cooldownUntil = 0
		updateButtonText()
	end)
end

local function applyEquippedPower()
	local rawName = localPlayer:GetAttribute("EquippedPower")
	if type(rawName) ~= "string" or rawName == "" then
		state.powerName = nil
		state.powerEntry = nil
		resetActivationState()
		refreshBinding()
		return
	end

	local powerName = rawName:lower()
	local powerEntry = SharedPowerConfigs.POWERS_BY_NAME[powerName]
	if not powerEntry then
		warn(`[POWER] Unknown EquippedPower attribute: {rawName}`)
		state.powerName = nil
		state.powerEntry = nil
		resetActivationState()
		refreshBinding()
		return
	end

	if state.powerName ~= powerName then
		resetActivationState()
	end
	state.powerName = powerName
	state.powerEntry = powerEntry
	refreshBinding()
end

local function applyRoundEligibility()
	state.roundEligible = localPlayer:GetAttribute(SharedPowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE) == true
	refreshBinding()
end

local function attachCharacter(character: Model?)
	if diedConnection then
		diedConnection:Disconnect()
		diedConnection = nil
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		state.alive = false
		refreshBinding()
		return
	end

	state.alive = humanoid.Health > 0
	diedConnection = humanoid.Died:Connect(function()
		state.alive = false
		refreshBinding()
	end)
	refreshBinding()
end

local function handleServerResponse(payload: any)
	if type(payload) ~= "table" or type(payload.sequenceId) ~= "number" then
		return
	end

	if payload.sequenceId ~= state.sequenceId then
		return
	end

	state.pendingResponse = false
	cancelPendingTimeout()

	local result = payload.result
	if type(result) ~= "table" then
		updateButtonText()
		return
	end

	if not state.powerEntry then
		updateButtonText()
		return
	end

	if result.success == true or result.reason == Reasons.OnCooldown then
		local remaining = state.powerEntry.cooldown
		if type(result.cooldownEndsAtUnixMs) == "number" and type(result.serverNowUnixMs) == "number" then
			remaining = math.max(0, (result.cooldownEndsAtUnixMs - result.serverNowUnixMs) / 1000)
		end

		if remaining > 0 then
			state.cooldownUntil = os.clock() + remaining
			startCooldown()
		else
			clearCooldown()
		end
		return
	end

	updateButtonText()
end

function Input.init(nextAbilityUi: ScreenGui, nextButton: TextButton)
	if initialized then
		return
	end
	initialized = true

	abilityUi = nextAbilityUi
	button = nextButton
	abilityUi.Enabled = false

	responseConnection = NetworkRouter:Listen(remoteName(), handleServerResponse)
	powerAttrConnection = localPlayer:GetAttributeChangedSignal("EquippedPower"):Connect(applyEquippedPower)
	roundEligibleConnection = localPlayer:GetAttributeChangedSignal(SharedPowerConfigs.ROUND_ELIGIBLE_ATTRIBUTE):Connect(applyRoundEligibility)
	characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
		attachCharacter(character)
	end)
	roundConnection = ClientEventBus:Connect("RoundUpdate", function(snapshot: any)
		if type(snapshot) ~= "table" then
			return
		end
		state.roundActive = snapshot.state == RoundConfigs.GAME_STATES.RoundActive
		refreshBinding()
	end)
	buttonConnection = button.MouseButton1Click:Connect(function()
		if not state.powerEntry then
			return
		end
		if not state.roundActive or not state.alive then
			return
		end
		if not state.roundEligible then
			return
		end
		if state.pendingResponse then
			return
		end
		if os.clock() < state.cooldownUntil then
			return
		end

		state.sequenceId += 1
		state.pendingResponse = true
		updateButtonText()

		cancelPendingTimeout()
		local thisSequence = state.sequenceId
		local cooldown = state.powerEntry.cooldown
		pendingTimeoutThread = task.delay(cooldown + Configs.PENDING_TIMEOUT_BUFFER, function()
			if state.sequenceId == thisSequence and state.pendingResponse then
				warn(`[POWER] No ActivateResponse for seq={thisSequence}; ungreying button`)
				state.pendingResponse = false
				updateButtonText()
			end
		end)

		NetworkRouter:Call(remoteName(), {
			powerName = state.powerName,
			payload = {},
			sequenceId = thisSequence,
		})
	end)

	attachCharacter(localPlayer.Character)
	applyRoundEligibility()
	applyEquippedPower()

	task.spawn(function()
		local ok, snapshot = pcall(function()
			return NetworkRouter:Call("RoundGetSnapshot")
		end)
		if ok and type(snapshot) == "table" then
			state.roundActive = snapshot.state == RoundConfigs.GAME_STATES.RoundActive
			refreshBinding()
		end
	end)
end

function Input.destroy()
	if not initialized then
		return
	end
	initialized = false

	resetActivationState()

	if powerBound then
		InputRouter.unbindPower()
		powerBound = false
	end

	if roundConnection then
		roundConnection:Disconnect()
		roundConnection = nil
	end
	if powerAttrConnection then
		powerAttrConnection:Disconnect()
		powerAttrConnection = nil
	end
	if roundEligibleConnection then
		roundEligibleConnection:Disconnect()
		roundEligibleConnection = nil
	end
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
	if diedConnection then
		diedConnection:Disconnect()
		diedConnection = nil
	end
	if buttonConnection then
		buttonConnection:Disconnect()
		buttonConnection = nil
	end
	if responseConnection then
		responseConnection:Disconnect()
		responseConnection = nil
	end
end

return Input
