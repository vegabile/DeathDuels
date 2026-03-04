local Framework = require("../framework")
local describe = Framework.describe
local it = Framework.it
local expect = Framework.expect

local KnifeServiceFactory = require("./KnifeService")
local MockPlayer = require("../mocks/MockPlayer")

local function makeAction(name, cooldown)
	return { name = name, cooldown = cooldown or 0.5 }
end

--// Default time starts high to avoid false rate-limit on first action
--// (mirrors real tick() which returns epoch-scale values)
local DEFAULT_START_TIME = 1000

local function createTestService(overrides)
	overrides = overrides or {}

	local deps = {
		debugPrint = overrides.debugPrint or function() end,
		debugMode = overrides.debugMode or false,
		actionRegistry = overrides.actionRegistry or {
			Stab = makeAction("Stab", 0.5),
			Throw = makeAction("Throw", 0.5),
		},
		hasKnifeEquipped = overrides.hasKnifeEquipped or function() return true end,
		sendToClient = overrides.sendToClient or function() end,
		getTime = overrides.getTime or function() return DEFAULT_START_TIME end,
		rateLimitBuffer = overrides.rateLimitBuffer or 0.05,
	}

	return KnifeServiceFactory.new(deps)
end

return function()
	describe("KnifeService.OnPlayerAdded", function()
		it("creates player state", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			expect(service.GetPlayerState(player)).toBeTruthy()
		end)

		it("initializes state machine as unlocked", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local state = service.GetPlayerState(player)
			expect(state.stateMachine.isStabbing):toBe(false)
			expect(state.stateMachine.isThrowing):toBe(false)
		end)

		it("initializes lastActionTimestamp to zero", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			expect(service.GetPlayerState(player).lastActionTimestamp):toBe(0)
		end)

		it("initializes empty alreadyHit table", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local count = 0
			for _ in service.GetPlayerState(player).alreadyHit do
				count += 1
			end
			expect(count):toBe(0)
		end)

		it("each player gets independent state", function()
			local service = createTestService()
			local p1 = MockPlayer.new("Alice", 1)
			local p2 = MockPlayer.new("Bob", 2)
			service.OnPlayerAdded(p1)
			service.OnPlayerAdded(p2)

			expect(service.GetPlayerState(p1) ~= service.GetPlayerState(p2)):toBe(true)
		end)
	end)

	describe("KnifeService.OnPlayerRemoving", function()
		it("clears player state", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)
			service.OnPlayerRemoving(player)

			expect(service.GetPlayerState(player)).toBeNil()
		end)

		it("does not error for unknown player", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerRemoving(player)
		end)

		it("does not affect other players", function()
			local service = createTestService()
			local p1 = MockPlayer.new("Alice", 1)
			local p2 = MockPlayer.new("Bob", 2)
			service.OnPlayerAdded(p1)
			service.OnPlayerAdded(p2)
			service.OnPlayerRemoving(p1)

			expect(service.GetPlayerState(p1)).toBeNil()
			expect(service.GetPlayerState(p2)).toBeTruthy()
		end)
	end)

	describe("KnifeService.OnPlayerDied", function()
		it("resets state machine", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.OnPlayerDied(player)

			local state = service.GetPlayerState(player)
			expect(state.stateMachine.isStabbing):toBe(false)
			expect(state.stateMachine.isThrowing):toBe(false)
		end)

		it("clears alreadyHit table", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)
			service.OnPlayerDied(player)

			local count = 0
			for _ in service.GetPlayerState(player).alreadyHit do
				count += 1
			end
			expect(count):toBe(0)
		end)

		it("does not error for unknown player", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerDied(player)
		end)

		it("allows new actions after death reset", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.OnPlayerDied(player)
			currentTime = 100.5

			local result = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(result.rejected):toBe(false)
		end)
	end)

	describe("KnifeService.HandleActionRequest - payload validation", function()
		it("rejects nil payload", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, nil)
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("invalid_payload")
		end)

		it("rejects string payload", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, "attack!")
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("invalid_payload")
		end)

		it("rejects empty table", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, {})
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("invalid_payload")
		end)

		it("rejects payload with invalid action", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, { desiredAction = "Explode", sequenceId = 1 })
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("invalid_payload")
		end)

		it("rejects payload with missing sequenceId", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, { desiredAction = "Stab" })
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("invalid_payload")
		end)

		it("rejects when player has no state", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)

			local result = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("no_state")
		end)
	end)

	describe("KnifeService.HandleActionRequest - knife equip check", function()
		it("rejects when no knife equipped", function()
			local service = createTestService({
				hasKnifeEquipped = function() return false end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(result.rejected):toBe(true)
			expect(result.reason):toBe("no_knife")
		end)

		it("accepts when knife is equipped", function()
			local service = createTestService({
				hasKnifeEquipped = function() return true end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local result = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(result.rejected):toBe(false)
		end)
	end)

	describe("KnifeService.HandleActionRequest - rate limiting", function()
		it("rejects action within cooldown window", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local r1 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(r1.rejected):toBe(false)

			service.ResetAction(player, "Stab")
			currentTime = 100.3

			local r2 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(r2.rejected):toBe(true)
			expect(r2.reason):toBe("rate_limited")
		end)

		it("accepts action after cooldown elapsed", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")
			currentTime = 100.5

			local r2 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(r2.rejected):toBe(false)
		end)

		it("rate limit respects buffer tolerance", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
				rateLimitBuffer = 0.05,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")

			--// 0.45 = cooldown(0.5) - buffer(0.05), should pass
			currentTime = 100.45

			local r2 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(r2.rejected):toBe(false)
		end)

		it("rate limit rejects just under buffer threshold", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
				rateLimitBuffer = 0.05,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")

			--// 0.44 < cooldown(0.5) - buffer(0.05) = 0.45
			currentTime = 100.44

			local r2 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(r2.rejected):toBe(true)
			expect(r2.reason):toBe("rate_limited")
		end)

		it("rate limit is per-player", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local p1 = MockPlayer.new("Alice", 1)
			local p2 = MockPlayer.new("Bob", 2)
			service.OnPlayerAdded(p1)
			service.OnPlayerAdded(p2)

			service.HandleActionRequest(p1, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(p1, "Stab")
			currentTime = 100.1

			--// p2 hasn't acted yet, should not be rate limited
			local result = service.HandleActionRequest(p2, { desiredAction = "Stab", sequenceId = 1 })
			expect(result.rejected):toBe(false)
		end)
	end)

	describe("KnifeService.HandleActionRequest - state machine locking", function()
		it("rejects second action while first is active", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			--// Advance past rate limit but don't reset state machine
			currentTime = 100.5
			local r2 = service.HandleActionRequest(player, { desiredAction = "Throw", sequenceId = 2 })
			expect(r2.rejected):toBe(true)
			expect(r2.reason):toBe("state_locked")
		end)

		it("rejects duplicate action while locked", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			currentTime = 100.5
			local r2 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(r2.rejected):toBe(true)
			expect(r2.reason):toBe("state_locked")
		end)

		it("accepts after cooldown reset", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")
			currentTime = 100.5

			local r2 = service.HandleActionRequest(player, { desiredAction = "Throw", sequenceId = 2 })
			expect(r2.rejected):toBe(false)
		end)
	end)

	describe("KnifeService.HandleActionRequest - state override messages", function()
		it("sends state override on invalid payload", function()
			local overrideSent = false
			local service = createTestService({
				sendToClient = function(_, payload)
					if payload.payloadType == "StateOverride" then
						overrideSent = true
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Invalid", sequenceId = 1 })
			expect(overrideSent):toBe(true)
		end)

		it("sends state override on no knife equipped", function()
			local overrideSent = false
			local service = createTestService({
				hasKnifeEquipped = function() return false end,
				sendToClient = function(_, payload)
					if payload.payloadType == "StateOverride" then
						overrideSent = true
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(overrideSent):toBe(true)
		end)

		it("sends state override on rate limited", function()
			local overrideSent = false
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
				sendToClient = function(_, payload)
					if payload.payloadType == "StateOverride" then
						overrideSent = true
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")
			currentTime = 100.1
			overrideSent = false

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(overrideSent):toBe(true)
		end)

		it("sends state override on state locked", function()
			local overrideSent = false
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
				sendToClient = function(_, payload)
					if payload.payloadType == "StateOverride" then
						overrideSent = true
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			overrideSent = false
			currentTime = 100.5

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 2 })
			expect(overrideSent):toBe(true)
		end)

		it("state override includes correct sequenceId", function()
			local receivedSeqId = nil
			local service = createTestService({
				hasKnifeEquipped = function() return false end,
				sendToClient = function(_, payload)
					if payload.payloadType == "StateOverride" then
						receivedSeqId = payload.sequenceId
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 42 })
			expect(receivedSeqId):toBe(42)
		end)

		it("state override includes serialized state machine", function()
			local receivedState = nil
			local service = createTestService({
				hasKnifeEquipped = function() return false end,
				sendToClient = function(_, payload)
					if payload.payloadType == "StateOverride" then
						receivedState = payload.overriddenState
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(receivedState).toBeTruthy()
			expect(receivedState.isStabbing):toBe(false)
			expect(receivedState.isThrowing):toBe(false)
		end)
	end)

	describe("KnifeService.ResetAction", function()
		it("unlocks the state machine", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")

			local state = service.GetPlayerState(player)
			expect(state.stateMachine.isStabbing):toBe(false)
		end)

		it("sends CooldownReset to client", function()
			local resetSent = false
			local resetActionName = nil
			local service = createTestService({
				sendToClient = function(_, payload)
					if payload.payloadType == "CooldownReset" then
						resetSent = true
						resetActionName = payload.actionName
					end
				end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.ResetAction(player, "Stab")

			expect(resetSent):toBe(true)
			expect(resetActionName):toBe("Stab")
		end)

		it("does not error for unknown player", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.ResetAction(player, "Stab")
		end)
	end)

	describe("KnifeService full lifecycle", function()
		it("stab -> reset -> throw -> reset works", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local r1 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(r1.rejected):toBe(false)
			expect(r1.actionName):toBe("Stab")

			service.ResetAction(player, "Stab")
			currentTime = 100.5

			local r2 = service.HandleActionRequest(player, { desiredAction = "Throw", sequenceId = 2 })
			expect(r2.rejected):toBe(false)
			expect(r2.actionName):toBe("Throw")
		end)

		it("player dies mid-action, rejoins combat", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.OnPlayerDied(player)
			currentTime = 100.5

			local r2 = service.HandleActionRequest(player, { desiredAction = "Throw", sequenceId = 2 })
			expect(r2.rejected):toBe(false)
		end)

		it("player leaves and state is cleaned up", function()
			local service = createTestService()
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			service.OnPlayerRemoving(player)

			expect(service.GetPlayerState(player)).toBeNil()
		end)

		it("rapid fire spam is rate limited", function()
			local currentTime = 100
			local service = createTestService({
				getTime = function() return currentTime end,
			})
			local player = MockPlayer.new("TestPlayer", 1)
			service.OnPlayerAdded(player)

			local r1 = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = 1 })
			expect(r1.rejected):toBe(false)

			service.ResetAction(player, "Stab")

			local rejectedCount = 0
			for i = 2, 10 do
				currentTime = 100 + 0.05 * (i - 1)
				local r = service.HandleActionRequest(player, { desiredAction = "Stab", sequenceId = i })
				if r.rejected then
					rejectedCount += 1
				else
					service.ResetAction(player, "Stab")
				end
			end

			expect(rejectedCount > 0):toBe(true)
		end)
	end)

	Framework.summary()
end
