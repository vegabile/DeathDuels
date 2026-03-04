local MockProfileStore = {}

function MockProfileStore.new(shouldFailLoad)
	local store = {}

	function store:StartSessionAsync(_key)
		if shouldFailLoad then return nil end

		local profile = {}
		profile.Data = {
			Coin = 0,
			Knives = {},
			Guns = {},
		}

		local sessionEndCallbacks = {}

		profile.OnSessionEnd = {
			Connect = function(_, fn)
				table.insert(sessionEndCallbacks, fn)
			end,
		}

		function profile:AddUserId(_userId) end
		function profile:Reconcile() end

		function profile:EndSession()
			for _, cb in sessionEndCallbacks do
				cb()
			end
		end

		function profile:IsActive()
			return true
		end

		return profile
	end

	return store
end

return MockProfileStore
