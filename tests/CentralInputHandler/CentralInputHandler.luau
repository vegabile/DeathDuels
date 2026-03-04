--// Lune-compatible copy of CentralInputHandler logic

local CentralInputHandler = {}

function CentralInputHandler.new(validFlags)
	local self = {}
	local currentInputTable = {}

	function self.addInputConnection(inputFlag, scriptConnection)
		if not validFlags[inputFlag] then
			return false, "invalid_flag"
		end
		if currentInputTable[inputFlag] then
			return false, "already_exists"
		end

		currentInputTable[inputFlag] = scriptConnection
		return true, nil
	end

	function self.removeInputConnection(inputFlag)
		if not validFlags[inputFlag] then
			return false, "invalid_flag"
		end
		if not currentInputTable[inputFlag] then
			return false, "not_found"
		end

		currentInputTable[inputFlag] = nil
		return true, nil
	end

	function self.getConnection(inputFlag)
		return currentInputTable[inputFlag]
	end

	function self.getConnectionCount()
		local count = 0
		for _ in currentInputTable do
			count += 1
		end
		return count
	end

	return self
end

return CentralInputHandler
