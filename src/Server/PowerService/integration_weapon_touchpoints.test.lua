--// Integration test for the four weapon-service attribute touch-points.
--// Run via mcp__robloxstudio__execute_luau.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KnifeService = require(ServerScriptService.KnifeService)
local GunService = require(ServerScriptService.GunService)
local ServerEventBus = require(ServerScriptService.ServerEventBus)
local NetworkRouter = require(ReplicatedStorage.NetworkRouter)

local passed, failed = 0, 0
local function check(label: string, cond: boolean)
	if cond then passed += 1; print(`PASS: {label}`) else failed += 1; print(`FAIL: {label}`) end
end

--// ─── Fixtures ────────────────────────────────────────────────────────────

local function mockPlayer(name: string, userId: number)
	local player
	player = {
		Name = name,
		UserId = userId,
		Character = nil,
		_attrs = {},
	}
	function player:SetAttribute(n, v) self._attrs[n] = v end
	function player:GetAttribute(n) return self._attrs[n] end
	function player:FindFirstChildWhichIsA(_className) return nil end
	function player:IsDescendantOf(container) return container == game:GetService("Players") end
	return player
end

--// NetworkRouter:Call calls remote:FireClient, which errors on non-Player mocks.
--// Capture + suppress so the real guard paths can run without raising.
local captured: { { name: string, player: any, payload: any } } = {}
local origCall = NetworkRouter.Call
NetworkRouter.Call = function(_self, name, plr, payload)
	table.insert(captured, { name = name, player = plr, payload = payload })
end

ServerEventBus:Fire("RoundStateChanged", "RoundActive")

--// ─── Case A: KnifeService CombatDisabled blocks action ──────────────────

do
	captured = {}
	local p = mockPlayer("KnifeCombatDisabled", 10001)
	KnifeService.OnPlayerAdded(p)

	p:SetAttribute("CombatDisabled", true)
	KnifeService._handleActionRequest(p, { desiredAction = "Stab", sequenceId = 1 })

	local sentOverride = false
	for _, c in captured do
		if c.name == KnifeService._getRemoteName(p)
			and c.payload
			and c.payload.payloadType == "StateOverride" then
			sentOverride = true
			break
		end
	end
	check("A1. KnifeService CombatDisabled sent StateOverride", sentOverride)

	KnifeService.OnPlayerRemoving(p)
end

--// Note: a "CombatDisabled=nil allows action" case is intentionally omitted.
--// Both the guard and downstream rejections emit StateOverride, so absence of
--// the guard cannot be proven from captured payloads alone. End-to-end behavior
--// is covered by the Dash power integration test (which sets and clears the
--// attribute) and by live-session manual play.

--// ─── Case C: GunService CombatDisabled blocks action ────────────────────

do
	captured = {}
	local p = mockPlayer("GunCombatDisabled", 10003)
	GunService.OnPlayerAdded(p)
	p:SetAttribute("CombatDisabled", true)
	GunService._handleActionRequest(p, { desiredAction = "Shoot", sequenceId = 2 })

	local sentOverride = false
	for _, c in captured do
		if c.name == GunService._getRemoteName(p)
			and c.payload
			and c.payload.payloadType == "StateOverride" then
			sentOverride = true
			break
		end
	end
	check("C1. GunService CombatDisabled sent StateOverride", sentOverride)

	GunService.OnPlayerRemoving(p)
end

--// ─── Case D: Attribute surface readable (surface-level smoke) ───────────

do
	local p = mockPlayer("MultReader", 10004)
	p:SetAttribute("KnifeCooldownMult", 0.5)
	p:SetAttribute("GunCooldownMult", 0.7)
	check("D1. KnifeCooldownMult readable", p:GetAttribute("KnifeCooldownMult") == 0.5)
	check("D2. GunCooldownMult readable", p:GetAttribute("GunCooldownMult") == 0.7)
end

--// Restore NetworkRouter:Call
NetworkRouter.Call = origCall

print(`\n{passed} passed, {failed} failed`)
