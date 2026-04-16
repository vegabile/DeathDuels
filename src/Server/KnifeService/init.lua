local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local createWeaponService = require(ServerScriptService.WeaponServiceFactory)

local KnifeStateMachine = require(ReplicatedStorage.Knife.KnifeStateMachine)
local PayloadValidator = require(ReplicatedStorage.Knife.PayloadValidator)
local KnifeUtility = require(ReplicatedStorage.Knife.KnifeUtility)

local ServerConfigs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)

return createWeaponService({
	serviceName = "KnifeService",
	remotePrefix = "KnifeAction",
	stateMachineModule = KnifeStateMachine,
	payloadValidatorModule = PayloadValidator,
	findWeaponTool = function(character)
		return KnifeUtility.findKnifeTool(character)
	end,
	actionRegistryModule = ActionRegistry,
	serverConfigs = ServerConfigs,
	extraState = function()
		return { currentTickConnection = nil, alreadyHit = {} }
	end,
	onDied = function(state)
		if state.currentTickConnection then
			state.currentTickConnection:Disconnect()
			state.currentTickConnection = nil
		end
		state.alreadyHit = {}
	end,
	onRemoving = function(state)
		if state.currentTickConnection then
			state.currentTickConnection:Disconnect()
		end
	end,
})
