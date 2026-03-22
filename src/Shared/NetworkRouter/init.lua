local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkRouter = {}
local cache = {}
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local isServer = RunService:IsServer()

local initialized = false

--
function NetworkRouter:Init()
	if isServer then
		initialized = true
	end
end

function NetworkRouter:Get(name)
	if cache[name] then
		return cache[name]
	end
	if (isServer) then
		repeat
			task.wait()
		until initialized
	end

	if isServer then
		local remote = remotesFolder:WaitForChild(name, 5)
		if remote then
			cache[name] = remote
		end
		return remote
	else
		local remote = remotesFolder:WaitForChild(name, 10)
		assert(remote, "NetworkRouter: Remote '" .. name .. "' not found")
		cache[name] = remote
		return remote
	end
end

if isServer then
	function NetworkRouter:CreateRemoteFunction(name)
		assert(not cache[name], "NetworkRouter: '" .. name .. "' already exists")
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = remotesFolder
		cache[name] = rf
		return rf
	end

	function NetworkRouter:CreateRemoteEvent(name)
		assert(not cache[name], "NetworkRouter: '" .. name .. "' already exists")
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = remotesFolder
		cache[name] = re
		return re
	end

	function NetworkRouter:Listen(name, callback)
		local remote = self:Get(name)
		if remote:IsA("RemoteFunction") then
			remote.OnServerInvoke = callback
		elseif remote:IsA("RemoteEvent") then
			return remote.OnServerEvent:Connect(callback)
		end
	end

	function NetworkRouter:Call(name, player, ...)
		local remote = self:Get(name)
		if (remote:IsA("RemoteEvent")) then
			remote:FireClient(player, ...)
		end
	end
else
	function NetworkRouter:Call(name, ...)
		local remote = self:Get(name)
		if remote:IsA("RemoteFunction") then
			return remote:InvokeServer(...)
		elseif remote:IsA("RemoteEvent") then
			remote:FireServer(...)
		end
	end

	function NetworkRouter:Listen(name, callback)
		local remote = self:Get(name)
		if remote:IsA("RemoteEvent") then
			return remote.OnClientEvent:Connect(callback)
		end
	end
end

return NetworkRouter
