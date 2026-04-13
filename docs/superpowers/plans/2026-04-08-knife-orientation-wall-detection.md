# Knife Orientation & Wall Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the knife tumble end-over-end locked to its flight direction, and use continuous raycasting so it never passes through walls.

**Architecture:** Replace physics-based AngularVelocity with manual CFrame updates each heartbeat. Replace frame-delta raycast with full-line raycast from spawn origin. Single file change.

**Tech Stack:** Luau, Roblox Engine (RunService.Heartbeat, workspace:Raycast, CFrame)

---

## File Structure

- Modify: `src/Shared/Knife/ProjectileFactory.lua` — all changes live here

---

### Task 1: Update constants

**Files:**
- Modify: `src/Shared/Knife/ProjectileFactory.lua:14-16`

- [ ] **Step 1: Replace RAYCAST_LOOKAHEAD with SPIN_RATE**

Replace these lines (14-16):

```lua
--// Lookahead multiplier — cast further than frame delta to catch fast collisions
local RAYCAST_LOOKAHEAD = 1.5
--// Overlap params for the secondary GetPartsInPart check
```

With:

```lua
--// End-over-end tumble rate (rad/s) — matches the old AngularVelocity feel
local SPIN_RATE = math.pi * 4
--// Overlap params for the secondary GetPartsInPart check
```

- [ ] **Step 2: Commit**

```bash
git add src/Shared/Knife/ProjectileFactory.lua
git commit -m "refactor: replace RAYCAST_LOOKAHEAD with SPIN_RATE constant"
```

---

### Task 2: Remove AngularVelocity creation

**Files:**
- Modify: `src/Shared/Knife/ProjectileFactory.lua:88-96`

- [ ] **Step 1: Delete the AngularVelocity block**

Remove these lines (88-96):

```lua
	--// Tumble end-over-end around the knife's LOCAL right axis (X).
	--// Because the knife is already oriented along the throw direction,
	--// spinning on local X gives a realistic forward tumble.
	local angularVelocity = Instance.new("AngularVelocity")
	angularVelocity.MaxTorque = math.huge
	angularVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	angularVelocity.AngularVelocity = Vector3.new(math.pi * 4, 0, 0)
	angularVelocity.Attachment0 = attachment
	angularVelocity.Parent = clonedHandle
```

- [ ] **Step 2: Commit**

```bash
git add src/Shared/Knife/ProjectileFactory.lua
git commit -m "remove physics-based AngularVelocity from knife projectile"
```

---

### Task 3: Rewrite heartbeat loop — continuous raycast + deterministic tumble

**Files:**
- Modify: `src/Shared/Knife/ProjectileFactory.lua:115-208`

This is the core change. Replace the state variables and entire heartbeat loop.

- [ ] **Step 1: Replace state variables**

Replace these lines (115-117):

```lua
	local lastPosition = clonedHandle.Position
	local alreadyHitFromThrow: { [Player]: boolean } = {}
	local stuck = false
```

With:

```lua
	local spawnOrigin = clonedHandle.Position
	local alreadyHitFromThrow: { [Player]: boolean } = {}
	local stuck = false
	local elapsedTime = 0
```

- [ ] **Step 2: Replace the heartbeat connection**

Replace the entire heartbeat block (lines 150-208):

```lua
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if stuck or not clonedHandle.Parent then
			debugPrint(DEBUG, `[ProjectileFactory] Exiting heartbeat — stuck={stuck}, parent={clonedHandle.Parent}`)
			heartbeatConnection:Disconnect()
			return
		end

		local currentPosition = clonedHandle.Position
		local delta = currentPosition - lastPosition

		if delta.Magnitude > 0 then
			--// Primary detection: raycast from last position with lookahead
			--// The lookahead catches high-speed misses where the knife moves
			--// further than one frame's delta in a single step.
			local rayDirection = delta * RAYCAST_LOOKAHEAD
			local result = workspace:Raycast(lastPosition, rayDirection, raycastParams)

			if result then
				local handled = processHit(result)
				if handled then
					lastPosition = currentPosition
					return
				end
			end

			--// Secondary detection: overlap check at current position.
			--// Catches thin/small parts the raycast may thread through,
			--// and objects the knife is already inside.
			local touching = workspace:GetPartsInPart(clonedHandle, overlapParams)
			if #touching > 0 then
				for _, part in touching do
					--// Skip parts that are in the exclude list conceptually
					--// (other projectiles, effects, etc.)
					if part.CanCollide or part:GetAttribute("KnifeCollidable") then
						local partCharacter = part:FindFirstAncestorOfClass("Model")
						if partCharacter then
							local hitPlayer = Players:GetPlayerFromCharacter(partCharacter)
							if hitPlayer and hitPlayer ~= owner and not alreadyHitFromThrow[hitPlayer] then
								alreadyHitFromThrow[hitPlayer] = true
								stickAndCleanup(currentPosition, nil)
								if onHit then
									onHit(hitPlayer)
								end
								lastPosition = currentPosition
								return
							end
						else
							--// Non-player collidable part — stick
							stickAndCleanup(currentPosition, nil)
							lastPosition = currentPosition
							return
						end
					end
				end
			end
		end

		lastPosition = currentPosition
	end)
```

With:

```lua
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if stuck or not clonedHandle.Parent then
			debugPrint(DEBUG, `[ProjectileFactory] Exiting heartbeat — stuck={stuck}, parent={clonedHandle.Parent}`)
			heartbeatConnection:Disconnect()
			return
		end

		elapsedTime += dt
		local currentPosition = clonedHandle.Position

		--// Deterministic tumble: re-assert flight-direction orientation + end-over-end spin
		local baseCFrame = CFrame.new(currentPosition, currentPosition + direction)
		clonedHandle.CFrame = baseCFrame * CFrame.Angles(elapsedTime * SPIN_RATE, 0, 0)

		--// Primary detection: continuous raycast from spawn origin to current position.
		--// Covers the entire flight path every frame — thin walls cannot be skipped.
		local toCurrentPos = currentPosition - spawnOrigin
		if toCurrentPos.Magnitude > 0 then
			local result = workspace:Raycast(spawnOrigin, toCurrentPos, raycastParams)

			if result then
				local handled = processHit(result)
				if handled then
					return
				end
			end
		end

		--// Secondary detection: overlap check for player character hits.
		--// Characters have complex multi-part geometry that benefits from overlap checks.
		local touching = workspace:GetPartsInPart(clonedHandle, overlapParams)
		if #touching > 0 then
			for _, part in touching do
				if part.CanCollide or part:GetAttribute("KnifeCollidable") then
					local partCharacter = part:FindFirstAncestorOfClass("Model")
					if partCharacter then
						local hitPlayer = Players:GetPlayerFromCharacter(partCharacter)
						if hitPlayer and hitPlayer ~= owner and not alreadyHitFromThrow[hitPlayer] then
							alreadyHitFromThrow[hitPlayer] = true
							stickAndCleanup(currentPosition, nil)
							if onHit then
								onHit(hitPlayer)
							end
							return
						end
					end
				end
			end
		end
	end)
```

Key differences from old loop:
- Accepts `dt` parameter from Heartbeat
- Accumulates `elapsedTime` and sets CFrame each frame for deterministic tumble
- Raycasts from `spawnOrigin` to `currentPosition` (continuous) instead of `lastPosition` to `lastPosition + delta * LOOKAHEAD`
- Removes `lastPosition` tracking entirely
- Overlap check only handles player characters (no `else` branch for wall stick — continuous raycast handles walls)

- [ ] **Step 3: Commit**

```bash
git add src/Shared/Knife/ProjectileFactory.lua
git commit -m "feat: deterministic tumble + continuous raycast for knife projectile"
```

---

### Task 4: Final review and verify

- [ ] **Step 1: Read the full file and verify consistency**

Read `src/Shared/Knife/ProjectileFactory.lua` end-to-end. Verify:
- `RAYCAST_LOOKAHEAD` is not referenced anywhere
- `lastPosition` is not referenced anywhere
- `AngularVelocity` is not created anywhere
- `SPIN_RATE` is defined and used in the heartbeat
- `spawnOrigin` is defined and used in the heartbeat
- `elapsedTime` is defined, accumulated, and used for CFrame
- `stick()` function is unchanged
- `processHit()` function is unchanged
- `stickAndCleanup()` still passes `direction` to `stick()`

- [ ] **Step 2: Verify via execute_luau**

Use `mcp__robloxstudio__execute_luau` to read the module source and confirm it parses without syntax errors:

```lua
local src = game:GetService("ReplicatedStorage"):FindFirstChild("Knife")
    and game:GetService("ReplicatedStorage").Knife:FindFirstChild("ProjectileFactory")
if src then
    print("ProjectileFactory found, source length: " .. #src.Source)
else
    print("ProjectileFactory not found — check Argon sync")
end
```

- [ ] **Step 3: Final commit if any fixups were needed**

```bash
git add src/Shared/Knife/ProjectileFactory.lua
git commit -m "fix: address review findings in ProjectileFactory"
```

Skip this step if no fixups were needed.
