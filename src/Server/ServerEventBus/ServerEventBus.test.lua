local ServerEventBus = require(script.Parent)

local eventName = "__StickyReplayTest"
ServerEventBus:FireSticky(eventName, "ready", 7)

local replayedA, replayedB
local connection = ServerEventBus:Connect(eventName, function(a, b)
	replayedA = a
	replayedB = b
end, { replayLast = true })
connection:Disconnect()

assert(replayedA == "ready", "sticky event replays first arg")
assert(replayedB == 7, "sticky event replays second arg")

local lastA, lastB = ServerEventBus:GetLast(eventName)
assert(lastA == "ready", "GetLast returns first arg")
assert(lastB == 7, "GetLast returns second arg")

local fireCount = 0
local futureConnection = ServerEventBus:Connect("__FutureEventTest", function(a, b)
	fireCount += 1
	assert(a == "future", "future event forwards first arg")
	assert(b == 11, "future event forwards second arg")
end)
ServerEventBus:Fire("__FutureEventTest", "future", 11)
futureConnection:Disconnect()
ServerEventBus:Fire("__FutureEventTest", "future", 11)
assert(fireCount == 1, "Disconnect prevents future calls")

local missing = ServerEventBus:GetLast("__MissingStickyTest")
assert(missing == nil, "GetLast returns nil for missing sticky event")

print("[ServerEventBus.test] passed")
return true
