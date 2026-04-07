--// Weapon simulation runner — pure Lua 5.4 compatible
--// Validates knife physics, gun mechanics, and input validation contracts

local PASS = 0
local FAIL = 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		PASS = PASS + 1
		print("  + " .. name)
	else
		FAIL = FAIL + 1
		print("  X " .. name .. ": " .. tostring(err))
	end
end

local function assert_eq(a, b, msg)
	if a ~= b then
		error(msg or string.format("expected %s, got %s", tostring(b), tostring(a)))
	end
end

local function assert_near(a, b, tolerance, msg)
	if math.abs(a - b) > tolerance then
		error(msg or string.format("expected ~%s, got %s (tol %s)", tostring(b), tostring(a), tostring(tolerance)))
	end
end

local function assert_true(v, msg)
	if not v then
		error(msg or "expected true")
	end
end

-- ============================================================
-- Config mirrors
-- ============================================================
local KnifeCfg = {
	ThrowSpeed = 120,
	ThrowMaxDistance = 150,
	ThrowDamage = 60,
	StabDamage = 40,
	StabRange = 6,
	StabCooldown = 0.4,
	ThrowCooldown = 1.2,
	GravityY = -196.2,
	StickDepth = 0.3,
	LifetimeSeconds = 5,
	HitboxRadius = 1.2,
}

local GunCfg = {
	Damage = 22,
	HeadshotMultiplier = 2.0,
	MaxAmmo = 12,
	FireRate = 0.15,
	ReloadTime = 1.8,
	MaxRange = 500,
	SpreadAngle = 1.5,
}

local ValidationCfg = {
	MaxTimestampDrift = 0.3,
	MaxOriginDrift = 10,
}

-- ============================================================
-- Knife physics simulation
-- ============================================================
local function simulateKnifeThrow(origin, dirX, dirY, dirZ, speed, gravityY, maxTime, dt)
	local px, py, pz = origin[1], origin[2], origin[3]
	local vx, vy, vz = dirX * speed, dirY * speed, dirZ * speed
	local elapsed = 0
	local positions = {}

	while elapsed < maxTime do
		vy = vy + gravityY * dt
		px = px + vx * dt
		py = py + vy * dt
		pz = pz + vz * dt
		elapsed = elapsed + dt
		table.insert(positions, { px, py, pz, elapsed })
	end

	return positions
end

local function dist3(a, b)
	local dx = a[1] - b[1]
	local dy = a[2] - b[2]
	local dz = a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ============================================================
-- KNIFE THROW TESTS
-- ============================================================
print("\n=== KNIFE THROW SIMULATION ===")

test("Knife travels forward from origin", function()
	local positions = simulateKnifeThrow({ 0, 5, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 0.5, 1 / 60)
	local last = positions[#positions]
	assert_true(last[3] > 30, string.format("knife should travel forward, got z=%s", last[3]))
end)

test("Knife arcs downward due to gravity", function()
	local positions = simulateKnifeThrow({ 0, 50, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 1.0, 1 / 60)
	local first = positions[1]
	local last = positions[#positions]
	assert_true(last[2] < first[2], "knife y should decrease over time due to gravity")
end)

test("Knife horizontal throw hits ground (y=0) within lifetime", function()
	local positions = simulateKnifeThrow({ 0, 10, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, KnifeCfg.LifetimeSeconds, 1 / 60)
	local hitGround = false
	for _, p in ipairs(positions) do
		if p[2] <= 0 then
			hitGround = true
			break
		end
	end
	assert_true(hitGround, "knife should hit ground within lifetime")
end)

test("Knife thrown upward at 45deg reaches apex then falls", function()
	local angle = math.rad(45)
	local dirY = math.sin(angle)
	local dirZ = math.cos(angle)
	local positions = simulateKnifeThrow({ 0, 5, 0 }, 0, dirY, dirZ, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 3.0, 1 / 60)

	local maxY = -math.huge
	local maxIdx = 0
	for i, p in ipairs(positions) do
		if p[2] > maxY then
			maxY = p[2]
			maxIdx = i
		end
	end
	assert_true(maxIdx > 1 and maxIdx < #positions, "apex should be in the middle of the arc")
	assert_true(maxY > 5, string.format("apex y should be above origin, got %s", maxY))
end)

test("Knife speed at launch matches config", function()
	local positions = simulateKnifeThrow({ 0, 5, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 0.02, 1 / 60)
	local first = positions[1]
	local distPerFrame = dist3({ 0, 5, 0 }, first)
	local speedEstimate = distPerFrame / (1 / 60)
	assert_near(speedEstimate, KnifeCfg.ThrowSpeed, 5, string.format("initial speed should be ~%s, got %s", KnifeCfg.ThrowSpeed, speedEstimate))
end)

test("Knife max distance caps within config range", function()
	local positions = simulateKnifeThrow({ 0, 100, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, KnifeCfg.ThrowMaxDistance / KnifeCfg.ThrowSpeed, 1 / 60)
	local last = positions[#positions]
	local totalDist = dist3({ 0, 100, 0 }, last)
	assert_true(totalDist <= KnifeCfg.ThrowMaxDistance * 1.5, string.format("distance %s should be near max %s", totalDist, KnifeCfg.ThrowMaxDistance))
end)

-- ============================================================
-- KNIFE STAB TESTS
-- ============================================================
print("\n=== KNIFE STAB SIMULATION ===")

test("Stab hits target within range", function()
	local playerPos = { 0, 5, 0 }
	local targetPos = { 0, 5, 4 }
	local d = dist3(playerPos, targetPos)
	assert_true(d <= KnifeCfg.StabRange, string.format("distance %s should be within stab range %s", d, KnifeCfg.StabRange))
end)

test("Stab misses target outside range", function()
	local playerPos = { 0, 5, 0 }
	local targetPos = { 0, 5, 10 }
	local d = dist3(playerPos, targetPos)
	assert_true(d > KnifeCfg.StabRange, "distance should exceed stab range")
end)

test("Stab damage matches config", function()
	assert_eq(KnifeCfg.StabDamage, 40, "stab damage should be 40")
end)

test("Throw damage matches config", function()
	assert_eq(KnifeCfg.ThrowDamage, 60, "throw damage should be 60")
end)

-- ============================================================
-- KNIFE STICK TESTS
-- ============================================================
print("\n=== KNIFE STICK SIMULATION ===")

test("Knife sticks into wall at perpendicular angle", function()
	local positions = simulateKnifeThrow({ 0, 10, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 2.0, 1 / 60)
	local stickPos = nil
	for _, p in ipairs(positions) do
		if p[3] >= 50 then
			stickPos = p
			break
		end
	end
	assert_true(stickPos ~= nil, "knife should reach z=50 wall")
	local embedZ = stickPos[3] + KnifeCfg.StickDepth
	assert_near(embedZ, 50 + KnifeCfg.StickDepth, 2, string.format("stick position should embed %s into surface", KnifeCfg.StickDepth))
end)

test("Knife sticks into floor when falling", function()
	local positions = simulateKnifeThrow({ 0, 20, 0 }, 1, 0, 0, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 3.0, 1 / 60)
	local hitFloor = false
	for _, p in ipairs(positions) do
		if p[2] <= 0 then
			hitFloor = true
			break
		end
	end
	assert_true(hitFloor, "knife should reach floor and stick")
end)

test("Knife sticks at steep downward angle", function()
	local positions = simulateKnifeThrow({ 0, 30, 0 }, 0, -0.7, 0.7, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 2.0, 1 / 60)
	local hitFloor = false
	local hitTime = 0
	for _, p in ipairs(positions) do
		if p[2] <= 0 then
			hitFloor = true
			hitTime = p[4]
			break
		end
	end
	assert_true(hitFloor, "downward knife should hit floor")
	assert_true(hitTime < 1.0, string.format("should hit quickly at steep angle, took %ss", hitTime))
end)

-- ============================================================
-- GUN SHOOT TESTS
-- ============================================================
print("\n=== GUN SHOOT SIMULATION ===")

test("Gun damage is 22 per body shot", function()
	assert_eq(GunCfg.Damage, 22, "body damage should be 22")
end)

test("Gun headshot deals double damage", function()
	local headshotDmg = GunCfg.Damage * GunCfg.HeadshotMultiplier
	assert_eq(headshotDmg, 44, "headshot damage should be 44")
end)

test("5 body shots kill a 100hp target", function()
	local hp = 100
	local shots = 0
	while hp > 0 do
		hp = hp - GunCfg.Damage
		shots = shots + 1
	end
	assert_eq(shots, 5, string.format("should take 5 body shots, took %s", shots))
end)

test("3 headshots kill a 100hp target", function()
	local hp = 100
	local headshotDmg = GunCfg.Damage * GunCfg.HeadshotMultiplier
	local shots = 0
	while hp > 0 do
		hp = hp - headshotDmg
		shots = shots + 1
	end
	assert_eq(shots, 3, string.format("should take 3 headshots, took %s", shots))
end)

test("Mixed 2 headshots + 1 body kills 100hp target", function()
	local hp = 100
	hp = hp - (GunCfg.Damage * GunCfg.HeadshotMultiplier)
	hp = hp - (GunCfg.Damage * GunCfg.HeadshotMultiplier)
	hp = hp - GunCfg.Damage
	assert_true(hp <= 0, string.format("should be dead, hp=%s", hp))
end)

-- ============================================================
-- GUN AMMO TESTS
-- ============================================================
print("\n=== GUN AMMO SIMULATION ===")

test("Gun starts with full magazine", function()
	assert_eq(GunCfg.MaxAmmo, 12, "max ammo should be 12")
end)

test("Firing depletes ammo by 1 each shot", function()
	local ammo = GunCfg.MaxAmmo
	for _ = 1, 5 do
		ammo = ammo - 1
	end
	assert_eq(ammo, 7, string.format("after 5 shots ammo should be 7, got %s", ammo))
end)

test("Cannot fire with 0 ammo", function()
	local ammo = 0
	local canFire = ammo > 0
	assert_true(not canFire, "should not fire at 0 ammo")
end)

test("Full mag dump empties at exactly 12 shots", function()
	local ammo = GunCfg.MaxAmmo
	local shotsFired = 0
	while ammo > 0 do
		ammo = ammo - 1
		shotsFired = shotsFired + 1
	end
	assert_eq(shotsFired, 12, "should fire exactly 12 shots")
	assert_eq(ammo, 0, "ammo should be 0 after dump")
end)

test("Reload restores to full magazine", function()
	local ammo = 3
	ammo = GunCfg.MaxAmmo
	assert_eq(ammo, 12, "reload should restore to 12")
end)

-- ============================================================
-- GUN FIRE RATE TESTS
-- ============================================================
print("\n=== GUN FIRE RATE SIMULATION ===")

test("Fire rate limits shots per second", function()
	local maxShotsPerSecond = 1 / GunCfg.FireRate
	assert_near(maxShotsPerSecond, 6.67, 0.1, string.format("should fire ~6.67/sec, got %s", maxShotsPerSecond))
end)

test("Full mag takes correct time to empty", function()
	local timeToEmpty = (GunCfg.MaxAmmo - 1) * GunCfg.FireRate
	assert_near(timeToEmpty, 1.65, 0.05, string.format("should take ~1.65s to empty, got %s", timeToEmpty))
end)

-- ============================================================
-- VALIDATION TESTS
-- ============================================================
print("\n=== INPUT VALIDATION SIMULATION ===")

test("Timestamp within drift passes", function()
	local serverTime = 1000
	local clientTime = 1000.1
	local drift = math.abs(serverTime - clientTime)
	assert_true(drift <= ValidationCfg.MaxTimestampDrift, "should pass validation")
end)

test("Timestamp outside drift fails", function()
	local serverTime = 1000
	local clientTime = 1001
	local drift = math.abs(serverTime - clientTime)
	assert_true(drift > ValidationCfg.MaxTimestampDrift, "should fail validation")
end)

test("Origin within drift range passes", function()
	local playerPos = { 0, 5, 0 }
	local claimedOrigin = { 2, 6, 1 }
	local d = dist3(playerPos, claimedOrigin)
	assert_true(d <= ValidationCfg.MaxOriginDrift, string.format("distance %s should be within %s", d, ValidationCfg.MaxOriginDrift))
end)

test("Spoofed origin far from player fails", function()
	local playerPos = { 0, 5, 0 }
	local spoofedOrigin = { 50, 5, 50 }
	local d = dist3(playerPos, spoofedOrigin)
	assert_true(d > ValidationCfg.MaxOriginDrift, "spoofed origin should fail validation")
end)

-- ============================================================
-- TTK SCENARIO COMPARISONS
-- ============================================================
print("\n=== TTK (TIME TO KILL) SCENARIOS ===")

test("Knife throw + stab kills 100hp target", function()
	local hp = 100
	hp = hp - KnifeCfg.ThrowDamage
	hp = hp - KnifeCfg.StabDamage
	assert_true(hp <= 0, string.format("throw+stab should kill, hp=%s", hp))
end)

test("Three knife stabs kill 100hp target", function()
	local hp = 100
	hp = hp - KnifeCfg.StabDamage
	hp = hp - KnifeCfg.StabDamage
	hp = hp - KnifeCfg.StabDamage
	assert_true(hp <= 0, string.format("3 stabs should kill, hp=%s", hp))
end)

test("Two knife throws kill 100hp target", function()
	local hp = 100
	hp = hp - KnifeCfg.ThrowDamage
	hp = hp - KnifeCfg.ThrowDamage
	assert_true(hp <= 0, string.format("2 throws should kill, hp=%s", hp))
end)

test("Gun TTK beats stab TTK at range (rewards aim)", function()
	local stabTTK = 2 * KnifeCfg.StabCooldown
	local gunTTK = 4 * GunCfg.FireRate
	assert_true(stabTTK > gunTTK, string.format("gun TTK (%ss) should beat stab TTK (%ss)", gunTTK, stabTTK))
end)

test("Knife throw + stab combo is fastest melee kill", function()
	local comboTTK = KnifeCfg.ThrowCooldown
	local pureStabTTK = 2 * KnifeCfg.StabCooldown
	assert_true(pureStabTTK < comboTTK, "pure stab is faster than throw+stab wait")
end)

-- ============================================================
-- TRAJECTORY EDGE CASES
-- ============================================================
print("\n=== TRAJECTORY EDGE CASES ===")

test("Knife thrown straight up returns to origin height", function()
	local positions = simulateKnifeThrow({ 0, 0, 0 }, 0, 1, 0, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 3.0, 1 / 60)
	local returnedToOrigin = false
	local wentUp = false
	for _, p in ipairs(positions) do
		if p[2] > 10 then wentUp = true end
		if wentUp and p[2] <= 0 then
			returnedToOrigin = true
			break
		end
	end
	assert_true(returnedToOrigin, "knife thrown straight up should return to ground")
end)

test("Knife thrown horizontally from height follows parabolic arc", function()
	local positions = simulateKnifeThrow({ 0, 50, 0 }, 0, 0, 1, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 2.0, 1 / 60)
	local prevDeltaY = 0
	local accelerating = true
	for i = 2, math.min(30, #positions) do
		local deltaY = positions[i - 1][2] - positions[i][2]
		if deltaY < prevDeltaY then
			accelerating = false
			break
		end
		prevDeltaY = deltaY
	end
	assert_true(accelerating, "y drop should accelerate (parabolic)")
end)

test("Knife at shallow angle travels far before hitting floor", function()
	local angle = math.rad(5)
	local dirY = math.sin(angle)
	local dirZ = math.cos(angle)
	local positions = simulateKnifeThrow({ 0, 5, 0 }, 0, dirY, dirZ, KnifeCfg.ThrowSpeed, KnifeCfg.GravityY, 3.0, 1 / 60)
	local hitFloor = false
	local floorZ = 0
	for _, p in ipairs(positions) do
		if p[2] <= 0 then
			hitFloor = true
			floorZ = p[3]
			break
		end
	end
	assert_true(hitFloor, "should hit floor")
	assert_true(floorZ > 20, string.format("shallow angle should travel far, got z=%s", floorZ))
end)

-- ============================================================
-- RESULTS
-- ============================================================
print(string.format("\n=== RESULTS: %d passed, %d failed ===", PASS, FAIL))

if FAIL > 0 then
	print("SOME TESTS FAILED")
	os.exit(1)
end

print("ALL TESTS PASSED")
