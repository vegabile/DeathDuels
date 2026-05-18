local RoundScope = require(script.Parent.RoundScope)

local EffectUtil = {}

local attributeStacks = setmetatable({}, { __mode = "k" }) :: { [Player]: { [string]: { any } } }
local propertyStacks = setmetatable({}, { __mode = "k" }) :: { [Instance]: { [string]: { original: any, entries: { any } } } }
local playerCleanups = setmetatable({}, { __mode = "k" }) :: { [Player]: { [() -> ()]: boolean } }

local function bindPlayerCleanup(player: Player, cleanup: () -> ()): () -> ()
	local active = true
	local cleanups = playerCleanups[player]
	if not cleanups then
		cleanups = {}
		playerCleanups[player] = cleanups
	end

	local wrapped
	wrapped = function()
		if not active then
			return
		end
		active = false
		cleanups[wrapped] = nil
		cleanup()
	end

	cleanups[wrapped] = true
	local roundUnregister = RoundScope.RegisterCleanup(wrapped)
	return function()
		roundUnregister()
	end
end

local function getAttributeStack(player: Player, attributeName: string): { any }
	local perPlayer = attributeStacks[player]
	if not perPlayer then
		perPlayer = {}
		attributeStacks[player] = perPlayer
	end
	local stack = perPlayer[attributeName]
	if not stack then
		stack = {}
		perPlayer[attributeName] = stack
	end
	return stack
end

local function applyAttributeTop(player: Player, attributeName: string, stack: { any })
	if #stack == 0 then
		local perPlayer = attributeStacks[player]
		if perPlayer then
			perPlayer[attributeName] = nil
		end
		player:SetAttribute(attributeName, nil)
		return
	end
	player:SetAttribute(attributeName, stack[#stack].value)
end

function EffectUtil.TemporaryAttribute(player: Player, attributeName: string, value: any, durationSec: number): () -> ()
	local stack = getAttributeStack(player, attributeName)
	local token = {}
	table.insert(stack, {
		token = token,
		value = value,
	})
	applyAttributeTop(player, attributeName, stack)

	local unregister = bindPlayerCleanup(player, function()
		for i = #stack, 1, -1 do
			if stack[i].token == token then
				table.remove(stack, i)
				break
			end
		end
		applyAttributeTop(player, attributeName, stack)
	end)

	task.delay(durationSec, unregister)
	return unregister
end

local function getPropertyStack(instance: Instance, propertyName: string): { original: any, entries: { any } }
	local perInstance = propertyStacks[instance]
	if not perInstance then
		perInstance = {}
		propertyStacks[instance] = perInstance
	end
	local stack = perInstance[propertyName]
	if not stack then
		stack = {
			original = (instance :: any)[propertyName],
			entries = {},
		}
		perInstance[propertyName] = stack
	end
	return stack
end

local function applyPropertyTop(instance: Instance, propertyName: string, stack)
	if instance.Parent == nil then
		return
	end
	if #stack.entries == 0 then
		(instance :: any)[propertyName] = stack.original
		local perInstance = propertyStacks[instance]
		if perInstance then
			perInstance[propertyName] = nil
		end
		return
	end
	(instance :: any)[propertyName] = stack.entries[#stack.entries].value
end

function EffectUtil.TemporaryProperty(player: Player, instance: Instance, propertyName: string, value: any, durationSec: number): () -> ()
	local stack = getPropertyStack(instance, propertyName)
	local token = {}
	table.insert(stack.entries, {
		token = token,
		value = value,
	})
	applyPropertyTop(instance, propertyName, stack)

	local unregister = bindPlayerCleanup(player, function()
		for i = #stack.entries, 1, -1 do
			if stack.entries[i].token == token then
				table.remove(stack.entries, i)
				break
			end
		end
		applyPropertyTop(instance, propertyName, stack)
	end)

	task.delay(durationSec, unregister)
	return unregister
end

function EffectUtil.CleanupPlayer(player: Player)
	local cleanups = playerCleanups[player]
	if not cleanups then
		return
	end
	local cleanupList = {}
	for cleanup in cleanups do
		table.insert(cleanupList, cleanup)
	end
	for _, cleanup in cleanupList do
		cleanup()
	end
	playerCleanups[player] = nil
end

return EffectUtil
