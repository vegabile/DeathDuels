local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugUtility = require(ReplicatedStorage.DebugUtility)

local Configs = require(script.Configs)
local DEBUG = Configs.DEBUG_MODE
local debugPrint = DebugUtility.Print

local InputRouter = {}

local bindingGroups = {
	Knife = Configs.KnifeBindings,
	Gun = Configs.GunBindings,
}

function InputRouter.bindWeapon(weaponType: string, callback: (actionName: string) -> ())
	local group = bindingGroups[weaponType]
	if not group then
		warn(`[InputRouter] Unknown weapon type: {weaponType}`)
		return
	end

	for actionName, binding in group do
		local inputs = {}
		if binding.keyboard then table.insert(inputs, binding.keyboard) end
		if binding.mouseButton then table.insert(inputs, binding.mouseButton) end
		if binding.gamepad then table.insert(inputs, binding.gamepad) end

		ContextActionService:BindAction(
			binding.actionName,
			function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin then return end
				callback(actionName)
			end,
			binding.touchButton or false,
			table.unpack(inputs)
		)

		debugPrint(DEBUG, `[InputRouter] Bound {binding.actionName}`)
	end
end

function InputRouter.unbindWeapon(weaponType: string)
	local group = bindingGroups[weaponType]
	if not group then
		warn(`[InputRouter] Unknown weapon type: {weaponType}`)
		return
	end

	for _, binding in group do
		ContextActionService:UnbindAction(binding.actionName)
		debugPrint(DEBUG, `[InputRouter] Unbound {binding.actionName}`)
	end
end

function InputRouter.bindPower(callback: () -> ())
	local binding = Configs.PowerBindings.Activate
	local inputs = {}
	if binding.keyboard then table.insert(inputs, binding.keyboard) end
	if binding.gamepad then table.insert(inputs, binding.gamepad) end

	ContextActionService:UnbindAction(binding.actionName)
	ContextActionService:BindAction(
		binding.actionName,
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then return end
			callback()
		end,
		binding.touchButton or false,
		table.unpack(inputs)
	)

	debugPrint(DEBUG, `[InputRouter] Bound {binding.actionName}`)
end

function InputRouter.unbindPower()
	ContextActionService:UnbindAction(Configs.PowerBindings.Activate.actionName)
	debugPrint(DEBUG, `[InputRouter] Unbound {Configs.PowerBindings.Activate.actionName}`)
end

return InputRouter
