local ClientEventBus = {}

local listeners = {}
local stickyEvents = {}

function ClientEventBus:Fire(eventName, ...)
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

function ClientEventBus:FireSticky(eventName, ...)
	stickyEvents[eventName] = { ... }
	self:Fire(eventName, ...)
end

function ClientEventBus:GetLast(eventName)
	local args = stickyEvents[eventName]
	if not args then
		return nil
	end
	return unpack(args)
end

function ClientEventBus:Connect(eventName, callback, options)
	if not listeners[eventName] then
		listeners[eventName] = {}
	end

	local list = listeners[eventName]
	table.insert(list, callback)

	if options and options.replayLast then
		local args = stickyEvents[eventName]
		if args then
			task.spawn(function()
				callback(unpack(args))
			end)
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

return ClientEventBus
