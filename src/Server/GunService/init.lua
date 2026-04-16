local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local createWeaponService = require(ServerScriptService.WeaponServiceFactory)

local GunStateMachine = require(ReplicatedStorage.Gun.GunStateMachine)
local PayloadValidator = require(ReplicatedStorage.Gun.PayloadValidator)
local GunUtility = require(ReplicatedStorage.Gun.GunUtility)

local ServerConfigs = require(script.Configs)
local ActionRegistry = require(script.ActionRegistry)

return createWeaponService({
	serviceName = "GunService",
	remotePrefix = "GunAction",
	stateMachineModule = GunStateMachine,
	payloadValidatorModule = PayloadValidator,
	findWeaponTool = function(character)
		return GunUtility.findGunTool(character)
	end,
	actionRegistryModule = ActionRegistry,
	serverConfigs = ServerConfigs,
})
