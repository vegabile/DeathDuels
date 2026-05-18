local ServerEventBus = {}

local listeners = {}
local stickyEvents = {}

function ServerEventBus:Fire(eventName, ...)
	local list = listeners[eventName]
	if not list then
		return
	end
	local args = { ... }
	for _, callback in list do
		callback(unpack(args))
	end
end

function ServerEventBus:FireSticky(eventName, ...)
	stickyEvents[eventName] = { ... }
	self:Fire(eventName, ...)
end

function ServerEventBus:GetLast(eventName)
	local args = stickyEvents[eventName]
	if not args then
		return nil
	end
	return unpack(args)
end

function ServerEventBus:Connect(eventName, callback, options)
	if not listeners[eventName] then
		listeners[eventName] = {}
	end

	local list = listeners[eventName]
	table.insert(list, callback)

	if options and options.replayLast then
		local args = stickyEvents[eventName]
		if args then
			callback(unpack(args))
		end
	end

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
