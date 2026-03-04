local Framework = require("../framework")
local describe = Framework.describe
local it = Framework.it
local expect = Framework.expect

local CentralInputHandlerFactory = require("./CentralInputHandler")

local DEFAULT_FLAGS = {
	GunInput = true,
	KnifeInput = true,
}

local function createHandler(flags)
	return CentralInputHandlerFactory.new(flags or DEFAULT_FLAGS)
end

local function mockConnection(name)
	return { name = name or "mock" }
end

return function()
	describe("CentralInputHandler.addInputConnection", function()
		it("accepts valid KnifeInput flag", function()
			local handler = createHandler()
			local ok = handler.addInputConnection("KnifeInput", mockConnection())
			expect(ok):toBe(true)
		end)

		it("accepts valid GunInput flag", function()
			local handler = createHandler()
			local ok = handler.addInputConnection("GunInput", mockConnection())
			expect(ok):toBe(true)
		end)

		it("rejects invalid flag", function()
			local handler = createHandler()
			local ok, reason = handler.addInputConnection("InvalidFlag", mockConnection())
			expect(ok):toBe(false)
			expect(reason):toBe("invalid_flag")
		end)

		it("rejects empty string flag", function()
			local handler = createHandler()
			local ok, reason = handler.addInputConnection("", mockConnection())
			expect(ok):toBe(false)
			expect(reason):toBe("invalid_flag")
		end)

		it("rejects case-variant 'knifeinput'", function()
			local handler = createHandler()
			local ok, reason = handler.addInputConnection("knifeinput", mockConnection())
			expect(ok):toBe(false)
			expect(reason):toBe("invalid_flag")
		end)

		it("rejects duplicate registration", function()
			local handler = createHandler()
			handler.addInputConnection("KnifeInput", mockConnection())
			local ok, reason = handler.addInputConnection("KnifeInput", mockConnection())
			expect(ok):toBe(false)
			expect(reason):toBe("already_exists")
		end)

		it("stores the provided connection", function()
			local handler = createHandler()
			local conn = mockConnection("test-conn")
			handler.addInputConnection("KnifeInput", conn)

			expect(handler.getConnection("KnifeInput")):toBe(conn)
		end)

		it("can register both flags simultaneously", function()
			local handler = createHandler()
			handler.addInputConnection("KnifeInput", mockConnection("knife"))
			handler.addInputConnection("GunInput", mockConnection("gun"))

			expect(handler.getConnectionCount()):toBe(2)
		end)
	end)

	describe("CentralInputHandler.removeInputConnection", function()
		it("removes existing connection", function()
			local handler = createHandler()
			handler.addInputConnection("KnifeInput", mockConnection())
			local ok = handler.removeInputConnection("KnifeInput")
			expect(ok):toBe(true)
			expect(handler.getConnection("KnifeInput")).toBeNil()
		end)

		it("rejects invalid flag", function()
			local handler = createHandler()
			local ok, reason = handler.removeInputConnection("InvalidFlag")
			expect(ok):toBe(false)
			expect(reason):toBe("invalid_flag")
		end)

		it("rejects removal of non-existent connection", function()
			local handler = createHandler()
			local ok, reason = handler.removeInputConnection("KnifeInput")
			expect(ok):toBe(false)
			expect(reason):toBe("not_found")
		end)

		it("double removal fails on second attempt", function()
			local handler = createHandler()
			handler.addInputConnection("KnifeInput", mockConnection())
			handler.removeInputConnection("KnifeInput")
			local ok, reason = handler.removeInputConnection("KnifeInput")
			expect(ok):toBe(false)
			expect(reason):toBe("not_found")
		end)

		it("removing one flag does not affect the other", function()
			local handler = createHandler()
			handler.addInputConnection("KnifeInput", mockConnection("knife"))
			handler.addInputConnection("GunInput", mockConnection("gun"))
			handler.removeInputConnection("KnifeInput")

			expect(handler.getConnection("KnifeInput")).toBeNil()
			expect(handler.getConnection("GunInput")).toBeTruthy()
		end)
	end)

	describe("CentralInputHandler lifecycle", function()
		it("add -> remove -> re-add works", function()
			local handler = createHandler()
			local c1 = mockConnection("first")
			local c2 = mockConnection("second")

			handler.addInputConnection("KnifeInput", c1)
			handler.removeInputConnection("KnifeInput")
			handler.addInputConnection("KnifeInput", c2)

			expect(handler.getConnection("KnifeInput")):toBe(c2)
		end)

		it("starts with zero connections", function()
			local handler = createHandler()
			expect(handler.getConnectionCount()):toBe(0)
		end)

		it("counts connections correctly after add/remove", function()
			local handler = createHandler()
			handler.addInputConnection("KnifeInput", mockConnection())
			expect(handler.getConnectionCount()):toBe(1)

			handler.addInputConnection("GunInput", mockConnection())
			expect(handler.getConnectionCount()):toBe(2)

			handler.removeInputConnection("KnifeInput")
			expect(handler.getConnectionCount()):toBe(1)

			handler.removeInputConnection("GunInput")
			expect(handler.getConnectionCount()):toBe(0)
		end)
	end)

	describe("CentralInputHandler custom flags", function()
		it("works with single-flag config", function()
			local handler = createHandler({ OnlyFlag = true })
			local ok = handler.addInputConnection("OnlyFlag", mockConnection())
			expect(ok):toBe(true)
		end)

		it("rejects flags not in custom config", function()
			local handler = createHandler({ OnlyFlag = true })
			local ok, reason = handler.addInputConnection("KnifeInput", mockConnection())
			expect(ok):toBe(false)
			expect(reason):toBe("invalid_flag")
		end)

		it("works with empty flag config (rejects all)", function()
			local handler = createHandler({})
			local ok, reason = handler.addInputConnection("KnifeInput", mockConnection())
			expect(ok):toBe(false)
			expect(reason):toBe("invalid_flag")
		end)
	end)

	Framework.summary()
end
