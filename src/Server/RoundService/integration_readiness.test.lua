--// Integration test — drives the readiness flow against a real player.
--//
--// REQUIRES A LIVE TEST SESSION. Unlike the unit tests in this directory,
--// this file cannot run in the edit environment alone — it needs:
--//   1. GlobalConfigs.TEST_MODE = true (so executor uses template teleport data)
--//   2. At least one real Player joined to a running Studio test server
--//   3. RoundSystem stored in _G._testRoundSystem by the executor
--//
--// Per CLAUDE.md, playtests are normally avoided. This one integration test
--// is the narrow exception: the whole point is to exercise player:LoadCharacter()
--// and the real Roblox lifecycle, which cannot be mocked. If running a playtest
--// is not acceptable, skip this file and verify manually by watching server
--// output during development.
--//
--// Run via mcp__robloxstudio__execute_luau against a running session.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerReadiness = require(ServerScriptService.RoundService.PlayerReadiness)
local RoundOrchestrator = require(ServerScriptService.RoundService.RoundOrchestrator)
local Configs = require(ReplicatedStorage.Round.Configs)

local passed, failed = 0, 0

local function check(label: string, condition: boolean, detail: string?)
	if condition then
		print(`PASS: {label}`)
		passed += 1
	else
		print(`FAIL: {label}{if detail then " — " .. detail else ""}`)
		failed += 1
	end
end

-- ─── Find a live player ───────────────────────────────────────────────────────

local player = Players:GetPlayers()[1]
if not player then
	print("[integration] SKIPPED — no player in session. Join a TEST_MODE session first.")
	return
end

print(`[integration] Testing against player: {player.Name} (userId {player.UserId})`)

-- ─── Happy path: record becomes complete within grace ────────────────────────

do
	--// Wait up to READINESS_GRACE_FIRST_ROUND + margin for the record to complete.
	--// Grace is 20s in Configs; we allow 25s total to account for startup.
	local deadline = os.clock() + 25
	while not PlayerReadiness.isComplete(player) and os.clock() < deadline do
		task.wait(0.2)
	end

	check("integration: record exists for player", PlayerReadiness.getRecord(player) ~= nil)
	check("integration: isComplete after grace", PlayerReadiness.isComplete(player))

	local missing = PlayerReadiness.missingFacts(player)
	check(
		"integration: no missing facts",
		#missing == 0,
		"missing: " .. table.concat(missing, ", ")
	)
end

-- ─── Force-skip physical contract ─────────────────────────────────────────────

do
	local roundSystem = _G._testRoundSystem
	if not roundSystem then
		print("[integration] SKIPPED force-skip test — no _G._testRoundSystem")
	elseif not RoundOrchestrator._testApplySkipped then
		print("[integration] SKIPPED force-skip test — no _testApplySkipped hook")
	else
		local playerState = roundSystem._playerStates[player]
		if not playerState then
			print("[integration] SKIPPED force-skip test — no PlayerState (wrong round phase?)")
		elseif playerState.status ~= Configs.PLAYER_STATUSES.Alive then
			print(`[integration] SKIPPED force-skip test — player not Alive, status: {playerState.status}`)
		else
			RoundOrchestrator._testApplySkipped(roundSystem, player, playerState)

			check(
				"force-skip: status is Skipped",
				playerState.status == Configs.PLAYER_STATUSES.Skipped
			)

			local character = player.Character
			check("force-skip: character exists", character ~= nil)
			if character then
				local hrp = character:FindFirstChild("HumanoidRootPart")
				check("force-skip: HRP exists", hrp ~= nil)
				check("force-skip: HRP anchored", hrp ~= nil and hrp.Anchored == true)

				check(
					"force-skip: ForceField present",
					character:FindFirstChildOfClass("ForceField") ~= nil
				)

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				check("force-skip: Humanoid exists", humanoid ~= nil)
				check(
					"force-skip: WalkSpeed = 0",
					humanoid ~= nil and humanoid.WalkSpeed == 0
				)
			end

			local backpack = player:FindFirstChildOfClass("Backpack")
			check("force-skip: Backpack exists", backpack ~= nil)
			if backpack then
				local toolCount = 0
				for _, child in backpack:GetChildren() do
					if child:IsA("Tool") then toolCount += 1 end
				end
				check("force-skip: backpack empty of Tools", toolCount == 0)
			end
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
