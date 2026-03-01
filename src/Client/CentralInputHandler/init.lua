local CONFIGS = require(script.CONFIGS)
local DebugUtility = require(game:GetService("ReplicatedStorage").DebugUtility)

local DEBUG = CONFIGS.isDebugPrintOn
local debugPrint = DebugUtility.Print

--// Only one of each Input Flag.
local CURRENT_VALID_INPUT_FLAGS = {
	GunInput = true,
}

local currentInputTable: {[string]: RBXScriptSignal} = {}

local CentralInputHandler = {}

function CentralInputHandler.addInputConnection(inputFlag: string, scriptConnection: RBXScriptSignal)
	if not CURRENT_VALID_INPUT_FLAGS[inputFlag] then
		warn(`[CentralInputHandler] Attempted to add input script with invalid input flag: {inputFlag}`)
		return
	end
	if currentInputTable[inputFlag] then
		warn(`[CentralInputHandler] Attempted to add input script for {inputFlag}, but it already exists.`)
		return
	end

	currentInputTable[inputFlag] = scriptConnection
	debugPrint(DEBUG, `[CentralInputHandler] Added input connection for {inputFlag}`)
end

function CentralInputHandler.removeInputConnection(inputFlag: string)
	if not CURRENT_VALID_INPUT_FLAGS[inputFlag] then
		warn(`[CentralInputHandler] Attempted to remove input script with invalid input flag: {inputFlag}`)
		return
	end
	if not currentInputTable[inputFlag] then
		warn(`[CentralInputHandler] Attempted to remove input script for {inputFlag}, but it does not exist.`)
		return
	end

	currentInputTable[inputFlag] = nil
	debugPrint(DEBUG, `[CentralInputHandler] Removed input connection for {inputFlag}`)
end

return CentralInputHandler