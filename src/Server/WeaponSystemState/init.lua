local ServerScriptService = game:GetService("ServerScriptService")
local ServerEventBus = require(ServerScriptService.ServerEventBus)

local WeaponSystemState = {}

local _ready: boolean? = nil

ServerEventBus:Connect("WeaponSystemReady", function(isReady: boolean)
	_ready = isReady
end)

function WeaponSystemState.IsReady(): boolean
	if _ready ~= nil then
		return _ready
	end
	--// Startup race: weapon executor may not have fired yet. Bounded wait.
	local deadline = os.clock() + 5
	while _ready == nil and os.clock() < deadline do
		task.wait()
	end
	if _ready == nil then
		warn("[WeaponSystemState] No ready signal received within 5s — assuming not ready")
		return false
	end
	return _ready
end

--// Test-only: resets state between tests.
function WeaponSystemState._reset()
	_ready = nil
end

return WeaponSystemState
