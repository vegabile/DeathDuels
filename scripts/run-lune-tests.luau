local fs = require("@lune/fs")
local process = require("@lune/process")

local cwd = process.cwd

local function join(...)
	local parts = { ... }
	return table.concat(parts, "/"):gsub("//+", "/")
end

local moduleCache = {}
local nodesByPath = {}
local Vector3
local CFrame
local newNode

local CLASS_PARENTS = {
	Part = "BasePart",
	MeshPart = "BasePart",
	SpawnLocation = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Tool = "BackpackItem",
	BackpackItem = "Instance",
	Backpack = "Instance",
	Attachment = "Instance",
	Folder = "Instance",
	ModuleScript = "LuaSourceContainer",
	Script = "LuaSourceContainer",
	LocalScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	BindableEvent = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	Humanoid = "Instance",
	ForceField = "Instance",
	LinearVelocity = "Instance",
	WeldConstraint = "Instance",
	ParticleEmitter = "Instance",
	TeleportOptions = "Instance",
	Player = "Instance",
	Decal = "Instance",
}

local function classIsA(className, target)
	if className == target then
		return true
	end
	if target == "Instance" and className ~= nil then
		return true
	end
	local parent = CLASS_PARENTS[className]
	while parent do
		if parent == target then
			return true
		end
		parent = CLASS_PARENTS[parent]
	end
	return false
end

local function newSignal()
	local signal = {
		_connections = {},
	}

	function signal:Connect(callback)
		local connection = {
			Connected = true,
		}
		function connection:Disconnect()
			self.Connected = false
		end
		connection._callback = callback
		table.insert(self._connections, connection)
		return connection
	end

	function signal:Once(callback)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end

	function signal:Fire(...)
		local args = { ... }
		local snapshot = {}
		for _, connection in self._connections do
			table.insert(snapshot, connection)
		end
		for _, connection in snapshot do
			if connection.Connected then
				connection._callback(unpack(args))
			end
		end
	end

	function signal:Wait()
		return nil
	end

	return signal
end

local Node = {}
Node.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	if key == "Name" then
		return rawget(self, "_name")
	end
	if key == "ClassName" then
		return rawget(self, "_className")
	end
	local raw = rawget(self, key)
	if raw ~= nil then
		return raw
	end
	if key == "Event" and rawget(self, "_className") == "BindableEvent" then
		return rawget(self, "_event")
	end
	if key == "IsA" then
		return function(_, className)
			return classIsA(rawget(self, "_className"), className)
		end
	end
	if key == "FindFirstChild" then
		return function(_, childName)
			return rawget(self, "_children")[childName]
		end
	end
	if key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" then
		return function(_, className)
			for _, child in rawget(self, "_children") do
				if child:IsA(className) then
					return child
				end
			end
			return nil
		end
	end
	if key == "WaitForChild" then
		return function(_, childName)
			return rawget(self, "_children")[childName]
		end
	end
	if key == "GetChildren" then
		return function()
			local children = {}
			for _, child in rawget(self, "_children") do
				table.insert(children, child)
			end
			return children
		end
	end
	if key == "GetDescendants" then
		return function()
			local descendants = {}
			local function visit(node)
				for _, child in rawget(node, "_children") do
					table.insert(descendants, child)
					visit(child)
				end
			end
			visit(self)
			return descendants
		end
	end
	if key == "FindFirstAncestorOfClass" then
		return function(_, className)
			local parent = rawget(self, "_parent")
			while parent do
				if parent:IsA(className) then
					return parent
				end
				parent = parent.Parent
			end
			return nil
		end
	end
	if key == "SetAttribute" then
		return function(_, attributeName, value)
			rawget(self, "_attributes")[attributeName] = value
		end
	end
	if key == "GetAttribute" then
		return function(_, attributeName)
			return rawget(self, "_attributes")[attributeName]
		end
	end
	if key == "IsDescendantOf" then
		return function(_, ancestor)
			local parent = rawget(self, "_parent")
			while parent do
				if parent == ancestor then
					return true
				end
				parent = parent.Parent
			end
			return false
		end
	end
	if key == "Destroy" then
		return function()
			self.Parent = nil
			rawset(self, "_destroyed", true)
			for _, child in rawget(self, "_children") do
				child.Parent = nil
			end
			rawset(self, "_children", {})
		end
	end
	if key == "Clone" then
		return function()
			local clone
			local function cloneNode(source)
				local copy = newNode(source.Name, nil, source.ClassName, nil)
				for prop, value in source do
					if type(prop) == "string" and not prop:match("^_") and prop ~= "Parent" then
						copy[prop] = value
					end
				end
				for attr, value in rawget(source, "_attributes") do
					copy:SetAttribute(attr, value)
				end
				for _, child in rawget(source, "_children") do
					local childCopy = cloneNode(child)
					childCopy.Parent = copy
				end
				return copy
			end
			clone = cloneNode(self)
			return clone
		end
	end
	if key == "GetBoundingBox" then
		return function()
			local size = Vector3 and Vector3.new(1, 1, 1) or { X = 1, Y = 1, Z = 1, Magnitude = 1 }
			local cframe = CFrame and CFrame.new(0, 0, 0) or { Position = Vector3 and Vector3.new(0, 0, 0) }
			local handle = rawget(self, "_children").Handle
			if handle and handle.Size then
				size = handle.Size
				cframe = handle.CFrame or cframe
			end
			return cframe, size
		end
	end
	if key == "PivotTo" then
		return function(_, cframe)
			self.CFrame = cframe
		end
	end
	if key == "Fire" and rawget(self, "_className") == "BindableEvent" then
		return function(_, ...)
			rawget(self, "_event"):Fire(...)
		end
	end
	if key == "FireClient" or key == "FireAllClients" then
		return function(_, ...)
			self._lastFire = { ... }
			if rawget(self, "_className") == "RemoteEvent" then
				rawget(self, "OnClientEvent"):Fire(...)
			end
		end
	end
	if key == "FireServer" then
		return function(_, ...)
			self._lastFire = { ... }
			if rawget(self, "_className") == "RemoteEvent" then
				rawget(self, "OnServerEvent"):Fire(...)
			end
		end
	end
	if key == "InvokeServer" then
		return function(_, ...)
			if rawget(self, "OnServerInvoke") then
				return rawget(self, "OnServerInvoke")(...)
			end
			return nil
		end
	end
	if key == "SetTeleportData" then
		return function(_, teleportData)
			self.TeleportData = teleportData
		end
	end
	if key == "TakeDamage" and rawget(self, "_className") == "Humanoid" then
		return function(_, amount)
			self.Health = math.max(0, (self.Health or 100) - amount)
			if self.Health <= 0 and self.Died then
				self.Died:Fire()
			end
		end
	end
	return rawget(self, "_children")[key]
end

local function setParent(child, parent)
	local oldParent = rawget(child, "_parent")
	if oldParent then
		rawget(oldParent, "_children")[child.Name] = nil
	end
	rawset(child, "_parent", parent)
	if parent then
		rawget(parent, "_children")[child.Name] = child
	end
end

Node.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	if key == "Name" then
		local parent = rawget(self, "_parent")
		if parent then
			rawget(parent, "_children")[rawget(self, "_name")] = nil
		end
		rawset(self, "_name", value)
		if parent then
			rawget(parent, "_children")[value] = self
		end
		return
	end
	if key == "ClassName" then
		rawset(self, "_className", value)
		return
	end
	rawset(self, key, value)
end

function newNode(name, path, className, parent)
	local node = setmetatable({
		_name = name,
		_path = path,
		_className = className,
		_parent = parent,
		_children = {},
		_attributes = {},
	}, Node)
	if className == "BindableEvent" then
		node._event = newSignal()
	elseif className == "RemoteEvent" then
		node.OnServerEvent = newSignal()
		node.OnClientEvent = newSignal()
	elseif className == "Player" then
		node.CharacterAdded = newSignal()
	elseif className == "Humanoid" then
		node.Health = 100
		node.WalkSpeed = 16
		node.JumpPower = 50
		node.Died = newSignal()
	end
	if className == "Part" or className == "BasePart" then
		node.Touched = newSignal()
		node.Size = Vector3 and Vector3.new(1, 1, 1) or nil
		node.Position = Vector3 and Vector3.new(0, 0, 0) or nil
		node.CFrame = CFrame and CFrame.new(0, 0, 0) or nil
		node.Anchored = false
		node.CanCollide = true
		node.CanQuery = true
		node.Transparency = 0
		node.Massless = false
	end
	if path then
		nodesByPath[path] = node
	end
	if parent then
		setParent(node, parent)
	end
	return node
end

local function moduleNameFromFile(fileName)
	return fileName:gsub("%.lua$", ""):gsub("%.luau$", "")
end

local function initFileForDirectory(dirPath)
	local luaPath = join(dirPath, "init.lua")
	if fs.isFile(luaPath) then
		return luaPath
	end
	local luauPath = join(dirPath, "init.luau")
	if fs.isFile(luauPath) then
		return luauPath
	end
	return nil
end

local function buildTree(rootName, rootPath)
	local root = newNode(rootName, rootPath, "Folder", nil)

	local function addDirectory(parent, dirPath)
		for _, childName in fs.readDir(dirPath) do
			if childName == "init.lua" or childName == "init.luau" then
				continue
			end
			local childPath = join(dirPath, childName)
			if fs.isDir(childPath) then
				local initPath = initFileForDirectory(childPath)
				local child = newNode(childName, initPath or childPath, initPath and "ModuleScript" or "Folder", parent)
				addDirectory(child, childPath)
			elseif fs.isFile(childPath) and (childName:match("%.lua$") or childName:match("%.luau$")) then
				newNode(moduleNameFromFile(childName), childPath, "ModuleScript", parent)
			end
		end
	end

	addDirectory(root, rootPath)
	return root
end

local ReplicatedStorage = buildTree("ReplicatedStorage", join(cwd, "src/Shared"))
local ServerScriptService = buildTree("ServerScriptService", join(cwd, "src/Server"))

Vector3 = {}
local Vector3Metatable = {}
Vector3Metatable.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
	end
	if key == "Unit" then
		local magnitude = self.Magnitude
		if magnitude == 0 then
			return Vector3.new(0, 0, 0)
		end
		return Vector3.new(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
	end
	return Vector3[key]
end
Vector3Metatable.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Metatable.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Metatable.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	end
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	error("Vector3 multiplication only supports scalar operands")
end
Vector3Metatable.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end

function Vector3.new(x, y, z)
	return setmetatable({
		X = x or 0,
		Y = y or 0,
		Z = z or 0,
		__type = "Vector3",
	}, Vector3Metatable)
end

CFrame = {}
local CFrameMetatable = {}
CFrameMetatable.__index = function(self, key)
	if key == "LookVector" then
		return rawget(self, "_lookVector") or Vector3.new(0, 0, -1)
	end
	return CFrame[key]
end
CFrameMetatable.__mul = function(a, b)
	if type(b) == "table" and rawget(b, "__type") == "CFrame" then
		return CFrame.new(a.Position + b.Position)
	end
	return a
end
CFrameMetatable.__add = function(a, b)
	return CFrame.new(a.Position + b)
end

function CFrame.new(x, y, z)
	local position
	if type(x) == "table" and rawget(x, "__type") == "Vector3" then
		position = x
	else
		position = Vector3.new(x or 0, y or 0, z or 0)
	end
	return setmetatable({
		Position = position,
		__type = "CFrame",
	}, CFrameMetatable)
end

function CFrame.lookAt(origin, target)
	local direction = (target - origin).Unit
	local cframe = CFrame.new(origin)
	rawset(cframe, "_lookVector", direction)
	return cframe
end

local Color3 = {}
function Color3.new(r, g, b)
	return {
		R = r or 0,
		G = g or 0,
		B = b or 0,
		__type = "Color3",
	}
end

local Vector2 = {}
function Vector2.new(x, y)
	return {
		X = x or 0,
		Y = y or 0,
		__type = "Vector2",
	}
end

local NumberRange = {}
function NumberRange.new(min, max)
	return {
		Min = min,
		Max = max or min,
		__type = "NumberRange",
	}
end

local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(time, value)
	return {
		Time = time,
		Value = value,
		__type = "NumberSequenceKeypoint",
	}
end

local NumberSequence = {}
function NumberSequence.new(value)
	return {
		Value = value,
		__type = "NumberSequence",
	}
end

local ColorSequence = {}
function ColorSequence.new(value)
	return {
		Value = value,
		__type = "ColorSequence",
	}
end

local Enum = {
	RaycastFilterType = {
		Exclude = "Exclude",
	},
	ForceLimitMode = {
		Magnitude = "Magnitude",
	},
	Material = {
		Neon = "Neon",
	},
}

local RaycastParams = {}
function RaycastParams.new()
	return {}
end

local OverlapParams = {}
function OverlapParams.new()
	return {}
end

local delayedTasks = {}
local taskStub = {}
function taskStub.delay(duration, callback, ...)
	local token = {
		duration = duration,
		callback = callback,
		args = { ... },
		cancelled = false,
	}
	table.insert(delayedTasks, token)
	return token
end
function taskStub.cancel(token)
	if type(token) == "table" then
		token.cancelled = true
	end
end
function taskStub.spawn(callbackOrThread, ...)
	if type(callbackOrThread) == "thread" then
		local ok, err = coroutine.resume(callbackOrThread, ...)
		assert(ok, err)
		return callbackOrThread
	end
	local thread = coroutine.create(callbackOrThread)
	local ok, err = coroutine.resume(thread, ...)
	assert(ok, err)
	return thread
end
taskStub.defer = taskStub.spawn
function taskStub.wait()
	return 0
end

local testRuntime = {
	nowMs = nil,
}
function testRuntime.runDelayedTasks()
	local pending = delayedTasks
	delayedTasks = {}
	for _, token in pending do
		if not token.cancelled then
			token.cancelled = true
			token.callback(unpack(token.args))
		end
	end
end
function testRuntime.clearDelayedTasks()
	delayedTasks = {}
end
function testRuntime.setNowMs(nowMs)
	testRuntime.nowMs = nowMs
end
function testRuntime.setTick(now)
	testRuntime.tickNow = now
end

local DateTime = {}
function DateTime.now()
	return {
		UnixTimestampMillis = testRuntime.nowMs or math.floor(os.clock() * 1000),
	}
end

local Instance = {}
function Instance.new(className)
	return newNode(className, nil, className, nil)
end

local workspace = newNode("Workspace", nil, "Workspace", nil)
function workspace:Raycast()
	return self._raycastResult
end
function workspace:GetPartsInPart()
	return self._partsInPart or {}
end

local Players = newNode("Players", nil, "Players", nil)
function Players:GetPlayers()
	return self:GetChildren()
end
function Players:GetPlayerFromCharacter(character)
	for _, player in self:GetChildren() do
		if player.Character == character then
			return player
		end
	end
	return nil
end
function Players:GetPlayerByUserId(userId)
	for _, player in self:GetChildren() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local RunService = {
	Heartbeat = newSignal(),
	IsStudio = function()
		return true
	end,
	IsServer = function()
		return true
	end,
}

local TeleportService = {
	calls = {},
}
function TeleportService:TeleportAsync(placeId, players, options)
	table.insert(self.calls, {
		placeId = placeId,
		players = players,
		options = options,
	})
end

local Debris = {
	items = {},
}
function Debris:AddItem(instance, duration)
	table.insert(self.items, {
		instance = instance,
		duration = duration,
	})
end

local function newHashMap()
	return {
		values = {},
		GetAsync = function(self, key)
			return self.values[key]
		end,
		SetAsync = function(self, key, value)
			self.values[key] = value
		end,
		_reset = function(self)
			self.values = {}
		end,
	}
end

local MemoryStoreService = {
	_maps = {},
}
function MemoryStoreService:GetHashMap(name)
	if not self._maps[name] then
		self._maps[name] = newHashMap()
	end
	return self._maps[name]
end
function MemoryStoreService:_reset()
	for _, hashMap in self._maps do
		hashMap:_reset()
	end
end

local remotesFolder = newNode("Remotes", nil, "Folder", ReplicatedStorage)
local mapsFolder = newNode("Maps", nil, "Folder", ReplicatedStorage)

local function seedMap(mapName, spawnCount)
	local map = newNode(mapName, nil, "Model", mapsFolder)
	for i = 1, spawnCount do
		local redSlot = newNode(`RedSlot{i}`, nil, "Folder", map)
		local red = newNode("RedSpawn", nil, "Part", redSlot)
		red.Position = Vector3.new(i, 0, 0)
		red.CFrame = CFrame.new(red.Position)
		local blueSlot = newNode(`BlueSlot{i}`, nil, "Folder", map)
		local blue = newNode("BlueSpawn", nil, "Part", blueSlot)
		blue.Position = Vector3.new(-i, 0, 0)
		blue.CFrame = CFrame.new(blue.Position)
	end
	return map
end

seedMap("TestMap", 6)
seedMap("Skate Park", 6)
seedMap("Map3", 6)

local services = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	RunService = RunService,
	TeleportService = TeleportService,
	Players = Players,
	Debris = Debris,
	MemoryStoreService = MemoryStoreService,
	Workspace = workspace,
}

local gameStub = {
	PlaceId = 123,
	JobId = "lune-test-job",
	GetService = function(_, serviceName)
		local service = services[serviceName]
		assert(service ~= nil, `missing stub service: {serviceName}`)
		return service
	end,
}
setmetatable(gameStub, {
	__index = function(_, key)
		return services[key]
	end,
})

testRuntime.services = services
testRuntime.Instance = Instance
testRuntime.workspace = workspace
testRuntime.MemoryStoreService = MemoryStoreService
testRuntime.TeleportService = TeleportService
testRuntime.task = taskStub

local function luneTypeof(value)
	if type(value) == "table" and rawget(value, "__type") then
		return rawget(value, "__type")
	end
	if getmetatable(value) == Node then
		return "Instance"
	end
	return type(value)
end

local function makeEnvironment(scriptNode)
	local env = {}
	setmetatable(env, { __index = getfenv(0) })
	env.game = gameStub
	env.script = scriptNode
	env.Vector3 = Vector3
	env.Vector2 = Vector2
	env.CFrame = CFrame
	env.Color3 = Color3
	env.ColorSequence = ColorSequence
	env.DateTime = DateTime
	env.Enum = Enum
	env.Instance = Instance
	env.NumberRange = NumberRange
	env.NumberSequence = NumberSequence
	env.NumberSequenceKeypoint = NumberSequenceKeypoint
	env.OverlapParams = OverlapParams
	env.RaycastParams = RaycastParams
	env.task = taskStub
	env.tick = function()
		return testRuntime.tickNow or os.clock()
	end
	env.typeof = luneTypeof
	env.workspace = workspace
	env.__Test = testRuntime
	env.require = function(target)
		if type(target) == "table" and getmetatable(target) == Node then
			return loadModule(target)
		end
		return require(target)
	end
	return env
end

function loadModule(node)
	assert(node ~= nil, "attempted to require nil module")
	assert(node._className == "ModuleScript", `cannot require {node._name}: not a ModuleScript`)
	if moduleCache[node] ~= nil then
		return moduleCache[node]
	end

	local source = fs.readFile(node._path)
	local chunk, loadErr = loadstring(source, "@" .. node._path)
	assert(chunk, loadErr)
	setfenv(chunk, makeEnvironment(node))
	local result = chunk()
	if result == nil then
		result = true
	end
	moduleCache[node] = result
	return result
end

local testPaths = {}

local function collectTests(dirPath, relativeDir)
	for _, childName in fs.readDir(dirPath) do
		local childPath = join(dirPath, childName)
		local childRelativePath = join(relativeDir, childName)
		if fs.isDir(childPath) then
			collectTests(childPath, childRelativePath)
		elseif fs.isFile(childPath) and (childName:match("%.test%.lua$") or childName:match("%.test%.luau$")) then
			table.insert(testPaths, childRelativePath)
		end
	end
end

collectTests(join(cwd, "src/Shared"), "src/Shared")
collectTests(join(cwd, "src/Server"), "src/Server")
table.sort(testPaths)

local failed = 0
for _, relativePath in testPaths do
	local absolutePath = join(cwd, relativePath)
	local node = nodesByPath[absolutePath]
	assert(node, `missing test module node for {relativePath}`)
	local ok, err = pcall(loadModule, node)
	if ok then
		print(`[PASS] {relativePath}`)
	else
		failed += 1
		warn(`[FAIL] {relativePath}: {err}`)
	end
end

if failed > 0 then
	error(`{failed} Lune test(s) failed`)
end

print("[Lune] all focused tests passed")
