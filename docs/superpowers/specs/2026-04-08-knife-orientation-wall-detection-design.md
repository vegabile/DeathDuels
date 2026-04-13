# Knife Orientation & Wall Detection

## Problem

1. **Orientation:** The knife tumbles via physics-based `AngularVelocity`, which can drift the tumble axis away from the flight path. The knife should tumble end-over-end while the tumble axis stays locked to the throw direction.
2. **Wall detection:** The frame-delta raycast with `1.5x` lookahead can miss thin walls at `ThrowSpeed = 100` studs/s. The secondary `GetPartsInPart` check is unreliable for walls because the tumbling knife's collision box rotates each frame.

## Solution

All changes are in **one file**: `src/Shared/Knife/ProjectileFactory.lua`.

### Deterministic Tumble

Replace the physics-based `AngularVelocity` with manual CFrame updates each heartbeat frame.

**Remove:**
- `AngularVelocity` instance creation (lines 91-96 in current code)

**Add to heartbeat loop:**
- Track `elapsedTime` (accumulated `dt` from `Heartbeat`)
- Each frame, set:
  ```
  baseCFrame = CFrame.new(currentPos, currentPos + direction)
  clonedHandle.CFrame = baseCFrame * CFrame.Angles(elapsedTime * SPIN_RATE, 0, 0)
  ```
- `SPIN_RATE` = `math.pi * 4` (same rate as the old AngularVelocity, preserves visual feel)
- The `CFrame.new(pos, pos + dir)` re-asserts the flight-direction orientation every frame
- The `CFrame.Angles(x, 0, 0)` rotates on local X, producing end-over-end tumble locked to the flight axis

**Why manual instead of physics:** Physics-based angular velocity can drift the rotation axis over time due to solver interactions. Manual CFrame is deterministic — the tumble axis is re-derived from the throw direction every frame, so it can never drift.

### Continuous Raycast

Replace the frame-to-frame delta raycast with a full-line raycast from spawn origin to current position.

**Remove:**
- `RAYCAST_LOOKAHEAD` constant
- `lastPosition`-based raycast logic

**Add:**
- Store `spawnOrigin = clonedHandle.Position` at creation time
- Each heartbeat frame:
  ```
  local toCurrentPos = currentPosition - spawnOrigin
  local result = workspace:Raycast(spawnOrigin, toCurrentPos, raycastParams)
  ```
- This covers the entire flight path every frame — thin walls cannot be skipped regardless of speed or frame rate
- At `ThrowSpeed = 100` over `ProjectileMaxLifetime = 7s`, the max ray length is 700 studs — trivial performance cost

**Keep:** `GetPartsInPart` as secondary detection for player character hits only (characters have complex multi-part geometry that benefits from overlap checks).

### Stick Behavior (Unchanged)

`ProjectileFactory.stick` already:
- Orients the knife along the travel direction
- Embeds `EMBED_DEPTH` (0.5) studs into the surface
- Anchors the part and sets despawn timer

No changes needed.

## Constants

| Constant | Value | Notes |
|----------|-------|-------|
| `SPIN_RATE` | `math.pi * 4` | Same as old AngularVelocity rate |
| `EMBED_DEPTH` | `0.5` | Unchanged |

**Removed:** `RAYCAST_LOOKAHEAD` (no longer needed)

## Scope

- Single file change: `src/Shared/Knife/ProjectileFactory.lua`
- No API changes — `spawnProjectile` and `stick` signatures stay the same
- No changes to server/client ThrowAction, KnifeProjectileHandler, or any other file
- Shared by both client cosmetic projectile and server authoritative projectile
