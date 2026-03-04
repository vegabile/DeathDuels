local Framework = require("../framework")
local describe = Framework.describe
local it = Framework.it
local expect = Framework.expect

local DataServiceFactory = require("./DataService")
local MockProfileStore = require("../mocks/MockProfileStore")
local MockPlayer = require("../mocks/MockPlayer")

local function createTestService(overrides)
	overrides = overrides or {}
	local guidCounter = 0

	local deps = {
		debugPrint = overrides.debugPrint or function() end,
		debugMode = overrides.debugMode or false,
		playerStore = overrides.playerStore or MockProfileStore.new(false),
		generateGUID = overrides.generateGUID or function()
			guidCounter += 1
			return `guid-{guidCounter}`
		end,
		isPlayerInGame = overrides.isPlayerInGame or function() return true end,
		kickPlayer = overrides.kickPlayer or function() end,
	}

	return DataServiceFactory.new(deps)
end

-- GetProfile

describe("GetProfile", function()
	it("returns nil when no profile loaded", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		expect(service.GetProfile(player)).toBeNil()
	end)

	it("returns profile after OnPlayerAdded", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(service.GetProfile(player)).toBeTruthy()
	end)

	it("isolates profiles between players", function()
		local service = createTestService()
		local p1 = MockPlayer.new("Alice", 1)
		local p2 = MockPlayer.new("Bob", 2)
		service.OnPlayerAdded(p1)
		service.OnPlayerAdded(p2)

		expect(service.GetProfile(p1)).toBeTruthy()
		expect(service.GetProfile(p2)).toBeTruthy()
		expect(service.GetProfile(p1) ~= service.GetProfile(p2)):toBe(true)
	end)

	it("returns nil after OnPlayerRemoving", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.OnPlayerRemoving(player)

		expect(service.GetProfile(player)).toBeNil()
	end)
end)

-- GetData

describe("GetData", function()
	it("returns nil when no profile loaded", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		expect(service.GetData(player)).toBeNil()
	end)

	it("returns data after OnPlayerAdded", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(service.GetData(player)).toBeTruthy()
	end)

	it("returns default schema values", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local data = service.GetData(player)
		expect(data.Coin):toBe(0)
		expect(#data.Knives):toBe(0)
		expect(#data.Guns):toBe(0)
	end)

	it("returns nil after session end", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		local profile = service.GetProfile(player)
		profile:EndSession()

		expect(service.GetData(player)).toBeNil()
	end)

	it("returns independent data per player", function()
		local service = createTestService()
		local p1 = MockPlayer.new("Alice", 1)
		local p2 = MockPlayer.new("Bob", 2)
		service.OnPlayerAdded(p1)
		service.OnPlayerAdded(p2)

		service.AddCoins(p1, 100)

		expect(service.GetData(p1).Coin):toBe(100)
		expect(service.GetData(p2).Coin):toBe(0)
	end)
end)

-- OnPlayerAdded

describe("OnPlayerAdded", function()
	it("kicks player when profile fails to load", function()
		local kicked = false
		local service = createTestService({
			playerStore = MockProfileStore.new(true),
			kickPlayer = function() kicked = true end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(kicked):toBe(true)
		expect(service.GetProfile(player)).toBeNil()
	end)

	it("stores profile when player is in game", function()
		local service = createTestService({
			isPlayerInGame = function() return true end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(service.GetProfile(player)).toBeTruthy()
	end)

	it("ends session when player left before load completed", function()
		local sessionEnded = false
		local store = MockProfileStore.new(false)
		local originalStart = store.StartSessionAsync

		store.StartSessionAsync = function(self, key)
			local profile = originalStart(self, key)
			local originalEnd = profile.EndSession
			profile.EndSession = function(...)
				sessionEnded = true
				return originalEnd(...)
			end
			return profile
		end

		local service = createTestService({
			playerStore = store,
			isPlayerInGame = function() return false end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(sessionEnded):toBe(true)
		expect(service.GetProfile(player)).toBeNil()
	end)

	it("clears profile on session end", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(service.GetProfile(player)).toBeTruthy()

		local profile = service.GetProfile(player)
		profile:EndSession()

		expect(service.GetProfile(player)).toBeNil()
	end)

	it("kicks with correct reason on failed load", function()
		local kickReason = nil
		local service = createTestService({
			playerStore = MockProfileStore.new(true),
			kickPlayer = function(_player, reason) kickReason = reason end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(kickReason):toBe("Unable to load your data. Please rejoin.")
	end)

	it("kicks with correct reason on session end", function()
		local kickReason = nil
		local service = createTestService({
			kickPlayer = function(_player, reason) kickReason = reason end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		local profile = service.GetProfile(player)
		profile:EndSession()

		expect(kickReason):toBe("Your data session ended. Please rejoin.")
	end)

	it("uses correct session key format", function()
		local sessionKey = nil
		local store = MockProfileStore.new(false)
		local originalStart = store.StartSessionAsync
		store.StartSessionAsync = function(self, key)
			sessionKey = key
			return originalStart(self, key)
		end

		local service = createTestService({ playerStore = store })
		local player = MockPlayer.new("TestPlayer", 42)
		service.OnPlayerAdded(player)

		expect(sessionKey):toBe("Player_42")
	end)
end)

-- OnPlayerRemoving

describe("OnPlayerRemoving", function()
	it("ends session for loaded profile", function()
		local sessionEnded = false
		local store = MockProfileStore.new(false)
		local originalStart = store.StartSessionAsync

		store.StartSessionAsync = function(self, key)
			local profile = originalStart(self, key)
			local originalEnd = profile.EndSession
			profile.EndSession = function(...)
				sessionEnded = true
				return originalEnd(...)
			end
			return profile
		end

		local service = createTestService({ playerStore = store })
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.OnPlayerRemoving(player)

		expect(sessionEnded):toBe(true)
	end)

	it("does nothing when no profile exists", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		--// Should not error
		service.OnPlayerRemoving(player)
	end)

	it("can be called twice without error", function()
		local endCount = 0
		local store = MockProfileStore.new(false)
		local originalStart = store.StartSessionAsync
		store.StartSessionAsync = function(self, key)
			local profile = originalStart(self, key)
			local originalEnd = profile.EndSession
			profile.EndSession = function(...)
				endCount += 1
				return originalEnd(...)
			end
			return profile
		end

		local service = createTestService({ playerStore = store })
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.OnPlayerRemoving(player)
		service.OnPlayerRemoving(player)

		--// EndSession only called once — second call finds no profile
		expect(endCount):toBe(1)
	end)
end)

-- AddCoins

describe("AddCoins", function()
	it("returns failure when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.AddCoins(player, 50)
		expect(result.successful):toBe(false)
		expect(result.errorMessage):toBe("Profile not found")
	end)

	it("adds coins to current amount", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 50)
		service.AddCoins(player, 30)

		local data = service.GetData(player)
		expect(data.Coin):toBe(80)
	end)

	it("returns successful on success", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.AddCoins(player, 50)
		expect(result.successful):toBe(true)
		expect(result.errorMessage).toBeNil()
	end)

	it("adding zero coins leaves balance unchanged", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 50)
		service.AddCoins(player, 0)

		expect(service.GetData(player).Coin):toBe(50)
	end)

	it("fails after player removed", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.OnPlayerRemoving(player)

		local result = service.AddCoins(player, 50)
		expect(result.successful):toBe(false)
	end)

	it("does not affect another player's coins", function()
		local service = createTestService()
		local p1 = MockPlayer.new("Alice", 1)
		local p2 = MockPlayer.new("Bob", 2)
		service.OnPlayerAdded(p1)
		service.OnPlayerAdded(p2)

		service.AddCoins(p1, 200)
		service.AddCoins(p2, 50)

		expect(service.GetData(p1).Coin):toBe(200)
		expect(service.GetData(p2).Coin):toBe(50)
	end)
end)

-- RemoveCoins

describe("RemoveCoins", function()
	it("returns failure when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.RemoveCoins(player, 50)
		expect(result.successful):toBe(false)
	end)

	it("removes coins from current amount", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 100)
		service.RemoveCoins(player, 30)

		local data = service.GetData(player)
		expect(data.Coin):toBe(70)
	end)

	it("allows negative coin balance", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.RemoveCoins(player, 50)

		local data = service.GetData(player)
		expect(data.Coin):toBe(-50)
	end)

	it("removing zero coins leaves balance unchanged", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 75)
		service.RemoveCoins(player, 0)

		expect(service.GetData(player).Coin):toBe(75)
	end)

	it("returns successful on success", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 100)
		local result = service.RemoveCoins(player, 30)
		expect(result.successful):toBe(true)
		expect(result.errorMessage).toBeNil()
	end)

	it("handles sequential add and remove to zero", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 100)
		service.RemoveCoins(player, 100)

		expect(service.GetData(player).Coin):toBe(0)
	end)
end)

-- GetKnifeById

describe("GetKnifeById", function()
	it("returns nil when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		expect(service.GetKnifeById(player, "some-id")).toBeNil()
	end)

	it("returns nil when knife not found", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(service.GetKnifeById(player, "nonexistent")).toBeNil()
	end)

	it("returns knife when found by id", function()
		local service = createTestService({
			generateGUID = function() return "knife-id-1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddKnife(player, "Bowie")

		local knife = service.GetKnifeById(player, "knife-id-1")
		expect(knife).toBeTruthy()
		expect(knife.name):toBe("Bowie")
	end)
end)

-- AddKnife

describe("AddKnife", function()
	it("returns failure when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.AddKnife(player, "Bowie")
		expect(result.successful):toBe(false)
	end)

	it("inserts knife with generated id and correct name", function()
		local service = createTestService({
			generateGUID = function() return "test-guid" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddKnife(player, "Bowie")

		local knife = service.GetKnifeById(player, "test-guid")
		expect(knife).toBeTruthy()
		expect(knife.name):toBe("Bowie")
		expect(knife.equipped):toBe(false)
	end)

	it("generates unique ids for multiple knives", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `knife-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddKnife(player, "Dagger")

		expect(service.GetKnifeById(player, "knife-1")).toBeTruthy()
		expect(service.GetKnifeById(player, "knife-2")).toBeTruthy()
		expect(service.GetKnifeById(player, "knife-1").name):toBe("Bowie")
		expect(service.GetKnifeById(player, "knife-2").name):toBe("Dagger")
	end)

	it("returns successful on success", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.AddKnife(player, "Bowie")
		expect(result.successful):toBe(true)
		expect(result.errorMessage).toBeNil()
	end)
end)

-- RemoveKnife

describe("RemoveKnife", function()
	it("returns failure when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.RemoveKnife(player, "some-id")
		expect(result.successful):toBe(false)
	end)

	it("returns failure when knife id not found", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.RemoveKnife(player, "nonexistent")
		expect(result.successful):toBe(false)
		expect(result.errorMessage):toBe("Knife not found")
	end)

	it("removes knife by id", function()
		local service = createTestService({
			generateGUID = function() return "knife-to-remove" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddKnife(player, "Bowie")

		local result = service.RemoveKnife(player, "knife-to-remove")
		expect(result.successful):toBe(true)
		expect(service.GetKnifeById(player, "knife-to-remove")).toBeNil()
	end)

	it("does not remove other knives", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `knife-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddKnife(player, "Dagger")
		service.RemoveKnife(player, "knife-1")

		expect(service.GetKnifeById(player, "knife-1")).toBeNil()
		expect(service.GetKnifeById(player, "knife-2")).toBeTruthy()
	end)

	it("removing same knife twice fails on second attempt", function()
		local service = createTestService({
			generateGUID = function() return "once-only" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddKnife(player, "Bowie")

		local first = service.RemoveKnife(player, "once-only")
		local second = service.RemoveKnife(player, "once-only")

		expect(first.successful):toBe(true)
		expect(second.successful):toBe(false)
		expect(second.errorMessage):toBe("Knife not found")
	end)

	it("removes middle item from list of three", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `k-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "First")
		service.AddKnife(player, "Middle")
		service.AddKnife(player, "Last")
		service.RemoveKnife(player, "k-2")

		expect(service.GetKnifeById(player, "k-1")).toBeTruthy()
		expect(service.GetKnifeById(player, "k-2")).toBeNil()
		expect(service.GetKnifeById(player, "k-3")).toBeTruthy()
		expect(#service.GetData(player).Knives):toBe(2)
	end)

	it("can remove all knives one by one", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `k-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "A")
		service.AddKnife(player, "B")
		service.AddKnife(player, "C")

		service.RemoveKnife(player, "k-1")
		service.RemoveKnife(player, "k-2")
		service.RemoveKnife(player, "k-3")

		expect(#service.GetData(player).Knives):toBe(0)
	end)
end)

-- GetGunById

describe("GetGunById", function()
	it("returns nil when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		expect(service.GetGunById(player, "some-id")).toBeNil()
	end)

	it("returns nil when gun not found", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		expect(service.GetGunById(player, "nonexistent")).toBeNil()
	end)

	it("returns gun when found by id", function()
		local service = createTestService({
			generateGUID = function() return "gun-id-1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddGun(player, "Revolver")

		local gun = service.GetGunById(player, "gun-id-1")
		expect(gun).toBeTruthy()
		expect(gun.name):toBe("Revolver")
	end)
end)

-- AddGun

describe("AddGun", function()
	it("returns failure when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.AddGun(player, "Revolver")
		expect(result.successful):toBe(false)
	end)

	it("inserts gun with generated id and correct name", function()
		local service = createTestService({
			generateGUID = function() return "test-gun-guid" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddGun(player, "Revolver")

		local gun = service.GetGunById(player, "test-gun-guid")
		expect(gun).toBeTruthy()
		expect(gun.name):toBe("Revolver")
		expect(gun.equipped):toBe(false)
	end)

	it("generates unique ids for multiple guns", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `gun-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "Revolver")
		service.AddGun(player, "Shotgun")

		expect(service.GetGunById(player, "gun-1")).toBeTruthy()
		expect(service.GetGunById(player, "gun-2")).toBeTruthy()
		expect(service.GetGunById(player, "gun-1").name):toBe("Revolver")
		expect(service.GetGunById(player, "gun-2").name):toBe("Shotgun")
	end)

	it("returns successful on success", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.AddGun(player, "Revolver")
		expect(result.successful):toBe(true)
		expect(result.errorMessage).toBeNil()
	end)
end)

-- RemoveGun

describe("RemoveGun", function()
	it("returns failure when no profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.RemoveGun(player, "some-id")
		expect(result.successful):toBe(false)
	end)

	it("returns failure when gun id not found", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.RemoveGun(player, "nonexistent")
		expect(result.successful):toBe(false)
		expect(result.errorMessage):toBe("Gun not found")
	end)

	it("removes gun by id", function()
		local service = createTestService({
			generateGUID = function() return "gun-to-remove" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddGun(player, "Revolver")

		local result = service.RemoveGun(player, "gun-to-remove")
		expect(result.successful):toBe(true)
		expect(service.GetGunById(player, "gun-to-remove")).toBeNil()
	end)

	it("does not remove other guns", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `gun-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "Revolver")
		service.AddGun(player, "Shotgun")
		service.RemoveGun(player, "gun-1")

		expect(service.GetGunById(player, "gun-1")).toBeNil()
		expect(service.GetGunById(player, "gun-2")).toBeTruthy()
	end)

	it("removing same gun twice fails on second attempt", function()
		local service = createTestService({
			generateGUID = function() return "once-only" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddGun(player, "Revolver")

		local first = service.RemoveGun(player, "once-only")
		local second = service.RemoveGun(player, "once-only")

		expect(first.successful):toBe(true)
		expect(second.successful):toBe(false)
		expect(second.errorMessage):toBe("Gun not found")
	end)

	it("removes middle item from list of three", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `g-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "First")
		service.AddGun(player, "Middle")
		service.AddGun(player, "Last")
		service.RemoveGun(player, "g-2")

		expect(service.GetGunById(player, "g-1")).toBeTruthy()
		expect(service.GetGunById(player, "g-2")).toBeNil()
		expect(service.GetGunById(player, "g-3")).toBeTruthy()
		expect(#service.GetData(player).Guns):toBe(2)
	end)
end)

-- Cross-cutting edge cases

describe("Mixed operations", function()
	it("knives and guns do not interfere with each other", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `id-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddGun(player, "Revolver")
		service.AddKnife(player, "Dagger")

		expect(#service.GetData(player).Knives):toBe(2)
		expect(#service.GetData(player).Guns):toBe(1)
	end)

	it("all operations fail after session end", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		local profile = service.GetProfile(player)
		profile:EndSession()

		expect(service.AddCoins(player, 50).successful):toBe(false)
		expect(service.RemoveCoins(player, 10).successful):toBe(false)
		expect(service.AddKnife(player, "Bowie").successful):toBe(false)
		expect(service.AddGun(player, "Revolver").successful):toBe(false)
		expect(service.GetKnifeById(player, "any")).toBeNil()
		expect(service.GetGunById(player, "any")).toBeNil()
	end)

	it("coin operations and item operations are independent", function()
		local service = createTestService({
			generateGUID = function() return "item-1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 500)
		service.AddKnife(player, "Bowie")
		service.RemoveCoins(player, 200)

		expect(service.GetData(player).Coin):toBe(300)
		expect(#service.GetData(player).Knives):toBe(1)
	end)

	it("removing one player does not affect another", function()
		local service = createTestService()
		local p1 = MockPlayer.new("Alice", 1)
		local p2 = MockPlayer.new("Bob", 2)
		service.OnPlayerAdded(p1)
		service.OnPlayerAdded(p2)

		service.AddCoins(p1, 100)
		service.AddCoins(p2, 200)
		service.OnPlayerRemoving(p1)

		expect(service.GetData(p1)).toBeNil()
		expect(service.GetData(p2).Coin):toBe(200)
	end)

	it("data persists across many operations", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `id-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		for i = 1, 10 do
			service.AddCoins(player, i)
		end
		for i = 1, 5 do
			service.AddKnife(player, `Knife_{i}`)
		end
		service.RemoveKnife(player, "id-3")
		service.RemoveKnife(player, "id-5")

		--// 1+2+3+4+5+6+7+8+9+10 = 55
		expect(service.GetData(player).Coin):toBe(55)
		expect(#service.GetData(player).Knives):toBe(3)
	end)
end)

-- Coin edge cases

describe("Coin edge cases", function()
	it("adding negative coins decreases balance", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 100)
		service.AddCoins(player, -30)

		expect(service.GetData(player).Coin):toBe(70)
	end)

	it("removing negative coins increases balance", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.RemoveCoins(player, -50)

		expect(service.GetData(player).Coin):toBe(50)
	end)

	it("handles very large coin values", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 999999999)
		expect(service.GetData(player).Coin):toBe(999999999)
	end)

	it("handles deeply negative balance", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.RemoveCoins(player, 999999999)
		expect(service.GetData(player).Coin):toBe(-999999999)
	end)

	it("many small adds accumulate correctly", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		for _ = 1, 100 do
			service.AddCoins(player, 1)
		end
		expect(service.GetData(player).Coin):toBe(100)
	end)

	it("alternating add and remove settles to correct value", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		for _ = 1, 50 do
			service.AddCoins(player, 10)
			service.RemoveCoins(player, 3)
		end
		--// 50 * 10 - 50 * 3 = 350
		expect(service.GetData(player).Coin):toBe(350)
	end)

	it("AddCoins returns correct errorMessage for missing profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.AddCoins(player, 50)
		expect(result.errorMessage):toBe("Profile not found")
	end)

	it("RemoveCoins returns correct errorMessage for missing profile", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)

		local result = service.RemoveCoins(player, 50)
		expect(result.errorMessage):toBe("Profile not found")
	end)
end)

-- Item equipped state

describe("Item equipped state", function()
	it("new knives default to unequipped", function()
		local service = createTestService({
			generateGUID = function() return "k1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddKnife(player, "Bowie")

		expect(service.GetKnifeById(player, "k1").equipped):toBe(false)
	end)

	it("new guns default to unequipped", function()
		local service = createTestService({
			generateGUID = function() return "g1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddGun(player, "Revolver")

		expect(service.GetGunById(player, "g1").equipped):toBe(false)
	end)

	it("knife schema has correct fields", function()
		local service = createTestService({
			generateGUID = function() return "k-schema" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddKnife(player, "TestKnife")

		local knife = service.GetKnifeById(player, "k-schema")
		expect(knife.id):toBe("k-schema")
		expect(knife.name):toBe("TestKnife")
		expect(knife.equipped):toBe(false)
	end)

	it("gun schema has correct fields", function()
		local service = createTestService({
			generateGUID = function() return "g-schema" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)
		service.AddGun(player, "TestGun")

		local gun = service.GetGunById(player, "g-schema")
		expect(gun.id):toBe("g-schema")
		expect(gun.name):toBe("TestGun")
		expect(gun.equipped):toBe(false)
	end)
end)

-- Removing items with shared GUID namespace

describe("Cross-type item IDs", function()
	it("knife and gun can share same GUID without confusion", function()
		local callCount = 0
		local service = createTestService({
			generateGUID = function()
				callCount += 1
				return "shared-id"
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddGun(player, "Revolver")

		local knife = service.GetKnifeById(player, "shared-id")
		local gun = service.GetGunById(player, "shared-id")
		expect(knife).toBeTruthy()
		expect(gun).toBeTruthy()
		expect(knife.name):toBe("Bowie")
		expect(gun.name):toBe("Revolver")
	end)

	it("removing knife does not remove gun with same id", function()
		local service = createTestService({
			generateGUID = function() return "same-id" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddGun(player, "Revolver")
		service.RemoveKnife(player, "same-id")

		expect(service.GetKnifeById(player, "same-id")).toBeNil()
		expect(service.GetGunById(player, "same-id")).toBeTruthy()
	end)

	it("removing gun does not remove knife with same id", function()
		local service = createTestService({
			generateGUID = function() return "same-id" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddGun(player, "Revolver")
		service.RemoveGun(player, "same-id")

		expect(service.GetGunById(player, "same-id")).toBeNil()
		expect(service.GetKnifeById(player, "same-id")).toBeTruthy()
	end)
end)

-- Removing first and last items in lists

describe("List removal boundary cases", function()
	it("removes first item from list of three guns", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `g-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "First")
		service.AddGun(player, "Second")
		service.AddGun(player, "Third")
		service.RemoveGun(player, "g-1")

		expect(service.GetGunById(player, "g-1")).toBeNil()
		expect(service.GetGunById(player, "g-2")).toBeTruthy()
		expect(service.GetGunById(player, "g-3")).toBeTruthy()
		expect(#service.GetData(player).Guns):toBe(2)
	end)

	it("removes last item from list of three guns", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `g-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "First")
		service.AddGun(player, "Second")
		service.AddGun(player, "Third")
		service.RemoveGun(player, "g-3")

		expect(service.GetGunById(player, "g-1")).toBeTruthy()
		expect(service.GetGunById(player, "g-2")).toBeTruthy()
		expect(service.GetGunById(player, "g-3")).toBeNil()
		expect(#service.GetData(player).Guns):toBe(2)
	end)

	it("removes only item from single-item knife list", function()
		local service = createTestService({
			generateGUID = function() return "only" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Solo")
		service.RemoveKnife(player, "only")

		expect(#service.GetData(player).Knives):toBe(0)
	end)

	it("can re-add after removing all guns", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `g-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "First")
		service.RemoveGun(player, "g-1")
		expect(#service.GetData(player).Guns):toBe(0)

		service.AddGun(player, "Second")
		expect(#service.GetData(player).Guns):toBe(1)
		expect(service.GetGunById(player, "g-2").name):toBe("Second")
	end)

	it("can remove all guns one by one", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `g-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "A")
		service.AddGun(player, "B")
		service.AddGun(player, "C")

		service.RemoveGun(player, "g-1")
		service.RemoveGun(player, "g-2")
		service.RemoveGun(player, "g-3")

		expect(#service.GetData(player).Guns):toBe(0)
	end)
end)

-- Multi-player stress tests

describe("Multi-player isolation", function()
	it("five players with independent inventories", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `item-{counter}`
			end,
		})

		local players = {}
		for i = 1, 5 do
			players[i] = MockPlayer.new(`Player{i}`, i)
			service.OnPlayerAdded(players[i])
		end

		service.AddCoins(players[1], 100)
		service.AddKnife(players[2], "Bowie")
		service.AddGun(players[3], "Revolver")
		service.AddCoins(players[4], 500)
		service.AddKnife(players[5], "Dagger")

		expect(service.GetData(players[1]).Coin):toBe(100)
		expect(#service.GetData(players[1]).Knives):toBe(0)
		expect(#service.GetData(players[2]).Knives):toBe(1)
		expect(service.GetData(players[2]).Coin):toBe(0)
		expect(#service.GetData(players[3]).Guns):toBe(1)
		expect(service.GetData(players[4]).Coin):toBe(500)
		expect(#service.GetData(players[5]).Knives):toBe(1)
	end)

	it("removing middle player preserves others", function()
		local service = createTestService()
		local p1 = MockPlayer.new("P1", 1)
		local p2 = MockPlayer.new("P2", 2)
		local p3 = MockPlayer.new("P3", 3)

		service.OnPlayerAdded(p1)
		service.OnPlayerAdded(p2)
		service.OnPlayerAdded(p3)

		service.AddCoins(p1, 10)
		service.AddCoins(p2, 20)
		service.AddCoins(p3, 30)

		service.OnPlayerRemoving(p2)

		expect(service.GetData(p1).Coin):toBe(10)
		expect(service.GetData(p2)).toBeNil()
		expect(service.GetData(p3).Coin):toBe(30)
	end)
end)

-- Empty string and special character item names

describe("Item name edge cases", function()
	it("allows empty string knife name", function()
		local service = createTestService({
			generateGUID = function() return "k-empty" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.AddKnife(player, "")
		expect(result.successful):toBe(true)
		expect(service.GetKnifeById(player, "k-empty").name):toBe("")
	end)

	it("allows empty string gun name", function()
		local service = createTestService({
			generateGUID = function() return "g-empty" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local result = service.AddGun(player, "")
		expect(result.successful):toBe(true)
		expect(service.GetGunById(player, "g-empty").name):toBe("")
	end)

	it("handles special characters in knife name", function()
		local service = createTestService({
			generateGUID = function() return "k-special" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Knife <with> 'special' \"chars\" & stuff!")
		expect(service.GetKnifeById(player, "k-special").name):toBe("Knife <with> 'special' \"chars\" & stuff!")
	end)

	it("allows duplicate knife names with different IDs", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `k-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddKnife(player, "Bowie")
		service.AddKnife(player, "Bowie")

		expect(service.GetKnifeById(player, "k-1").name):toBe("Bowie")
		expect(service.GetKnifeById(player, "k-2").name):toBe("Bowie")
		expect(#service.GetData(player).Knives):toBe(2)
	end)

	it("allows duplicate gun names with different IDs", function()
		local counter = 0
		local service = createTestService({
			generateGUID = function()
				counter += 1
				return `g-{counter}`
			end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddGun(player, "Revolver")
		service.AddGun(player, "Revolver")

		expect(#service.GetData(player).Guns):toBe(2)
	end)
end)

-- GetData returns live reference

describe("Data reference behavior", function()
	it("GetData returns same reference on multiple calls", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local d1 = service.GetData(player)
		local d2 = service.GetData(player)
		expect(d1 == d2):toBe(true)
	end)

	it("mutations via GetData reference are visible", function()
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		service.AddCoins(player, 50)
		local data = service.GetData(player)
		expect(data.Coin):toBe(50)

		service.AddCoins(player, 25)
		expect(data.Coin):toBe(75)
	end)
end)

-- AfterEffects hooks are called

describe("AfterEffects hooks", function()
	it("calls _modifyCoinsAfterEffects on AddCoins", function()
		local hookCalled = false
		local hookAmount = nil
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local original = service._modifyCoinsAfterEffects
		service._modifyCoinsAfterEffects = function(p, amount)
			hookCalled = true
			hookAmount = amount
			return original(p, amount)
		end

		service.AddCoins(player, 50)
		expect(hookCalled):toBe(true)
		expect(hookAmount):toBe(50)
	end)

	it("calls _modifyKnivesAfterEffects on AddKnife", function()
		local hookCalled = false
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local original = service._modifyKnivesAfterEffects
		service._modifyKnivesAfterEffects = function(p, knives)
			hookCalled = true
			return original(p, knives)
		end

		service.AddKnife(player, "Bowie")
		expect(hookCalled):toBe(true)
	end)

	it("calls _modifyGunsAfterEffects on AddGun", function()
		local hookCalled = false
		local service = createTestService()
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local original = service._modifyGunsAfterEffects
		service._modifyGunsAfterEffects = function(p, guns)
			hookCalled = true
			return original(p, guns)
		end

		service.AddGun(player, "Revolver")
		expect(hookCalled):toBe(true)
	end)

	it("calls _modifyKnivesAfterEffects on RemoveKnife", function()
		local hookCallCount = 0
		local service = createTestService({
			generateGUID = function() return "k1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local original = service._modifyKnivesAfterEffects
		service._modifyKnivesAfterEffects = function(p, knives)
			hookCallCount += 1
			return original(p, knives)
		end

		service.AddKnife(player, "Bowie")
		service.RemoveKnife(player, "k1")
		--// Called once for add, once for remove
		expect(hookCallCount):toBe(2)
	end)

	it("calls _modifyGunsAfterEffects on RemoveGun", function()
		local hookCallCount = 0
		local service = createTestService({
			generateGUID = function() return "g1" end,
		})
		local player = MockPlayer.new("TestPlayer", 100)
		service.OnPlayerAdded(player)

		local original = service._modifyGunsAfterEffects
		service._modifyGunsAfterEffects = function(p, guns)
			hookCallCount += 1
			return original(p, guns)
		end

		service.AddGun(player, "Revolver")
		service.RemoveGun(player, "g1")
		expect(hookCallCount):toBe(2)
	end)
end)

return function()
	Framework.summary()
end
