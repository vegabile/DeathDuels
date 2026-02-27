local ServerEventBus = {}

local listeners = {}

function ServerEventBus:Fire(eventName, ...)
	local list = listeners[eventName]
	if not list then
		return
	end
	local args = { ... }
	for _, callback in list do
		task.spawn(function()
			callback(unpack(args))
		end)
	end
end

function ServerEventBus:Connect(eventName, callback)
	if not listeners[eventName] then
		listeners[eventName] = {}
	end

	local list = listeners[eventName]
	table.insert(list, callback)

	return {
		Disconnect = function()
			local index = table.find(list, callback)
			if index then
				table.remove(list, index)
			end
		end,
	}
end

return ServerEventBus
