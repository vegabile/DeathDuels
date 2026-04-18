# Weapon Animations — Design Spec

**Date:** 2026-04-17
**Status:** Approved
**Scope:** Wire humanoid-driven cosmetic animations into the Knife and Gun systems, with per-weapon configurability, marker-driven release timing, and a windup-delayed gameplay model.

---

## 1. Context

The current weapon system plays no animations (all `AnimationId` fields are empty strings). Every action — `Throw`, `Stab`, `Shoot` — fires gameplay *immediately* on click and the animation (if any) runs alongside as a decoration. Configs are weapon-type-wide: all knives share `ThrowAnimationId`, all guns share `ShootAnimationId`. There is no concept of per-weapon variants, chained animations, idle, or reload.

The user provided six animation IDs — four for the "Small Pistol" variant (Idle, ShootLeadIn, Shoot, Reload), two for knife throwing (Throw, AirSpin). AirSpin is descoped for this pass.

## 2. Animation IDs (initial set)

| Key | Weapon | Animation ID |
|---|---|---|
| `Throw` | Knife | `100789163917300` |
| `Idle` | SmallPistol | `86262836320062` |
| `ShootLeadIn` | SmallPistol | `109732491974921` |
| `Shoot` | SmallPistol | `77923963870629` |
| `Reload` | SmallPistol | `73493786997600` |

Stab, knife Idle, and AirSpin are not yet authored; profile entries exist but gracefully no-op when an ID is blank.

## 3. Key Decisions

| # | Decision | Chosen | Rationale |
|---|---|---|---|
| Q1 | Timing model | **Gameplay delayed by N seconds** | The projectile/raycast actually fires at the animation's release point, not at click time. Windup is real gameplay time. |
| Q2 | Release-point specification | **Hybrid: AnimationEvent marker with numeric fallback** | Marker is the authoring source of truth; numeric fallback keeps un-markered animations shippable. |
| Q3 | Config scoping | **Per-weapon profiles inside existing Knife/Gun Configs, keyed by `tool.Name`; global `AnimationType` enum** | Keeps animation data next to other weapon data. Enum is globally shared so category keys don't drift. |
| Q4 | Shoot-flow chaining | **LeadIn → Shoot always plays on every click** | Simple, predictable. Rapid-fire concern deferred. |
| Q5 | Reload | **Cosmetic-only, manual `R` keybind** | Matches "treat animations as cosmetic." No magazine/ammo system. Cannot shoot while reloading. |
| Q6 | AirSpin | **Scrapped for this pass** | Procedural spin in `ProjectileFactory` stays. Would require rigging the knife Tool into a Model with AnimationController — out of scope. |
| Q7 | Cancellation | **Full cancel on any interrupt** | Death, unequip, round-end, StateOverride all cancel the pending release; no projectile fires. |

### Origin-handling decision (post-Section 3)

The projectile/bullet **spawns at the animated weapon CFrame** (what the player sees), but the **direction vector is computed from the rest-pose origin**: `direction = (aimTarget - restPoseOrigin).Unit`. Server authoritative math uses `restPoseOrigin` + `direction`. The client-supplied `spawnCFrame` is visual-only and is not trusted by the server. At typical target distances the angular difference between "from animated" and "from rest" is negligible, so the trajectory reads naturally while gameplay stays deterministic.

### Cooldown decision

Every action's effective cooldown = `max(animationLength, configuredFloor)` on the client. The floor values in config (`StabCooldown = 5`, etc.) remain as the server-side rate limit. Server is authoritative on the floor; the client naturally takes longer when an animation is longer.

---

## 4. Architecture

### 4.1 New modules

**`src/Shared/Animations/AnimationType.lua`** — frozen enum module:

```lua
return table.freeze({
    Idle        = "Idle",
    Throw       = "Throw",
    Stab        = "Stab",
    ShootLeadIn = "ShootLeadIn",
    Shoot       = "Shoot",
    Reload      = "Reload",
})
```

Single source of truth for animation category keys. Extending the system later = add one line here.

**`src/Shared/Animations/Configs.lua`** — global animation system config:

```lua
return {
    MarkerNames = { Release = "Release" },
    DefaultReleaseTime   = 0.2,   --// fallback when no profile.releaseTime AND no marker
    ReleaseTimeoutBuffer = 0.25,  --// hard timeout if marker never arrives
    MaxRestOriginDistance = 8,    --// server validation bound for restOrigin vs HRP
}
```

Renaming `"Release"` here flips every call site at once.

**`src/Shared/Animations/AnimationProfile.lua`** — pure lookup helper:

```lua
AnimationProfile.resolve(toolName: string, profilesTable: table, animationType: string)
    → { id: string, releaseTime: number? } | nil
```

No side effects. `warn` + return `nil` on unknown tool/type.

### 4.2 Extended configs

**`src/Shared/Knife/Configs.lua`** — add `AnimationProfiles`:

```lua
AnimationProfiles = {
    Knife = {
        [AnimationType.Throw] = { id = "rbxassetid://100789163917300", releaseTime = 0.2 },
        [AnimationType.Stab]  = { id = "" },
        [AnimationType.Idle]  = { id = "" },
    },
},
```

Remove the now-dead `StabAnimationId` and `ThrowAnimationId` top-level fields. Add `StabHitWindow = 1.0` (seconds — server-side hitbox window duration for stab).

**`src/Shared/Gun/Configs.lua`** — add `AnimationProfiles`:

```lua
AnimationProfiles = {
    SmallPistol = {
        [AnimationType.Idle]        = { id = "rbxassetid://86262836320062" },
        [AnimationType.ShootLeadIn] = { id = "rbxassetid://109732491974921" },
        [AnimationType.Shoot]       = { id = "rbxassetid://77923963870629", releaseTime = 0.12 },
        [AnimationType.Reload]      = { id = "rbxassetid://73493786997600" },
    },
},
```

Remove `ShootAnimationId`. Add `ReloadCooldown = 5` floor. Add `"Reload"` to `ValidActions`.

### 4.3 `AnimationController` upgrade

Return type changes from `{ stop }` to:

```lua
export type AnimationHandle = {
    stop: () -> (),
    track: AnimationTrack?,
    waitForMarker: (name: string) -> boolean,
    stopped: RBXScriptSignal?,
}
```

Existing callers that discard the return value keep working.

New methods:

- `AnimationController.play(character, animationId) → AnimationHandle` (unchanged signature; richer return).
- `AnimationController.playLooped(character, animationId) → AnimationHandle` — sets `track.Looped = true` before `Play()`. Used for Idle.
- `AnimationController.playChain(character, ids: {string}) → AnimationHandle` — plays each in sequence, awaiting `Stopped` between them. `handle.track` mutates as the chain advances; `handle.stop()` kills whatever's active.
- `AnimationController.preloadProfile(character, profile: {[string]: { id: string }}) → { [string]: number }` — loads every non-blank animation in the profile and returns `{ [animationId]: length }`. Used on tool equip to populate `AnimationLengthCache`.

`waitForMarker(name)` implementation: subscribe to `track:GetMarkerReachedSignal(name)` once, return `true` when fired. If `track.Stopped` fires first (animation killed / cancelled), return `false`. Single-shot; safe to call from any caller.

`AnimationLengthCache` — a module-local table `{ [animationId: string]: number }`, populated by `preloadProfile`. Exposed via `AnimationController.getCachedLength(animationId) → number?`.

### 4.4 Singleton enforcement (only one animation at a time)

The controller exposes a module-level **`currentActiveHandle: AnimationHandle?`** slot. Every public play method (`play`, `playLooped`, `playChain`) runs this sequence before starting its track:

1. If `currentActiveHandle ~= nil`, call `currentActiveHandle.stop()` — which tears down its `AnimationTrack`, fires any marker/stopped waiters with `false`, and nulls out the slot.
2. Build the new handle, assign it to `currentActiveHandle`, call `track:Play()`.

`handle.stop()` also clears the slot only if the slot still points at itself (avoids a stale handle zeroing out a newer one during re-entrancy).

New public helper: `AnimationController.stopCurrent()` — just `if currentActiveHandle then currentActiveHandle.stop() end`. Callers use this when they want a clean slate before the next play (e.g., gun controller tearing down idle before an action starts).

**Implications for idle:** Idle lives in the same slot as actions. When an action starts, the action's play automatically stops idle via the slot. When the action completes, the controller (GunController) explicitly re-plays idle, which re-occupies the slot. No separate "idle slot" is needed.

**Implications for `playChain`:** Internal chain progression is a single handle's responsibility — it owns two sequential tracks but occupies one slot. When the chain advances from track 1 to track 2, it swaps its internal track reference but does *not* clear the slot. External callers only see the chain handle.

### 4.5 Stale-callback guard (pending-action tokens)

The singleton slot prevents concurrent *playback* but does not prevent a **stale release waiter** — e.g., a fallback timer from cancelled action A firing after action B has started — from writing into the wrong pending-action state.

Each controller maintains:

- `pendingActionGeneration: number` — monotonically increasing counter, bumped on every `performAction` call and every `cancelPending` call.
- `pendingAction: { generation, sequenceId, restOffset, profile, action, release* timers } | nil` — the single pending-action record.

Every release waiter (marker, fallback timer, hard timeout) **captures the generation at spawn time** and checks it before firing:

```lua
local myGen = pendingActionGeneration
task.spawn(function()
    local fired = handle.waitForMarker(markerName)
    if myGen ~= pendingActionGeneration then return end  --// stale — abort silently
    if not fired then return end
    _onRelease(pendingAction)
end)
```

Same pattern for the `task.delay`-based fallback and hard timeout. Stale waiters exit cleanly without touching state. This matters because cancellation and subsequent actions can happen faster than `task.cancel` can always interrupt a scheduled delay.

---

## 5. Client Flow

### 5.1 Per-action windup → release (Throw, Shoot)

```
click
  ├── state machine locks (isThrowing / isShooting = true)
  ├── capture rest offset:
  │     restOffset = HRP.CFrame:ToObjectSpace(handle.CFrame)
  │     (read BEFORE track:Play() so animation has not yet moved anything)
  ├── pendingAction record stored: { sequenceId, restOffset, profile, action }
  ├── AnimationController.play(character, profile.id)  →  handle
  ├── spawn release waiter:
  │     markerFired = handle.waitForMarker(Configs.MarkerNames.Release)
  │     (runs in task.spawn; race with fallback timer)
  ├── spawn fallback timer:
  │     task.delay(profile.releaseTime or Configs.DefaultReleaseTime, ...)
  └── spawn hard timeout (last-resort safety):
        task.delay(releaseTime + Configs.ReleaseTimeoutBuffer, ...)

whichever release signal fires first:
  ├── cancel the other two waiters
  ├── read current HRP.CFrame
  ├── restOrigin  = (currentHRP * restOffset).Position
  ├── spawnCFrame = handle.CFrame        -- animated, visual-only
  ├── aimTarget   = InputPosition.getInputPosition()
  ├── direction   = (aimTarget - restOrigin).Unit
  ├── spawn cosmetic client projectile from spawnCFrame with direction
  └── NetworkRouter:Call(remoteName, {
        desiredAction, directionVector = direction,
        restOrigin, spawnCFrame, sequenceId,
      })
```

State machine unlock + safety timeout mirror the current design (action cooldown + buffer).

### 5.2 Stab

No windup/release. Client plays the stab animation (if the ID is non-blank). Server authoritatively enables a `.Touched` connection on the knife's existing `Hitbox` for a fixed `StabHitWindow` duration (new config field in `Shared/Knife/Configs.lua`, default `1.0` — tune to match the authored animation length when it lands). Any non-ally `Player`'s character that touches the hitbox during that window is killed (`Humanoid.Health = 0`, `LastDamageSource` attribute set to attacker's UserId). One victim per stab via an `alreadyHit` set. The `.Touched` connection is torn down when the window expires (`task.delay(StabHitWindow, ...)`).

Why a static window instead of deriving from animation length: the server has no animation context (animations replicate, but reading the client's `AnimationTrack.Length` on the server is fragile and adds coupling for a feature the user labelled "cosmetic"). A static config value is simpler and fully server-owned. When the animation is authored and its length known, update `StabHitWindow` to match.

Client implementation: plays animation only. No `.Touched` handling on the client; the server owns the hit window.

### 5.3 Shoot chain (Small Pistol)

Click triggers `AnimationController.playChain(character, { leadInId, shootId })`. The release-marker waiter attaches to the *second* track (the Shoot animation). `handle.track` points to whichever track is currently playing — the waiter uses a small observer that binds its marker listener when `handle.track` becomes the Shoot track.

**Missing-ID fallback:**
- If `shootId` is blank: warn, skip the chain entirely, reject the action at the state machine level (no gameplay fires). The Shoot animation is mandatory for the Shoot action to execute — without it there is no release point.
- If only `leadInId` is blank: play Shoot directly (single-track), marker waits on it as normal.

This keeps "missing Shoot = no shooting" unambiguous rather than silently firing from a degraded flow.

### 5.4 Idle lifecycle (Gun)

- `onGunEquipped`: preload the tool's profile (`AnimationController.preloadProfile`), then `idleHandle = AnimationController.playLooped(character, profile.Idle.id)`.
- Before any other action starts: `idleHandle.stop()`.
- On `CooldownReset` / state machine reset back to clear: restart idle.
- `onGunUnequipped` / `onPlayerDied` / round state leaves `RoundActive`: stop idle, clear handle.

Knife has no idle in the initial animation set — skipped until authored.

### 5.5 Reload

- New action file `src/Client/GunController/Actions/ReloadAction.lua`, registered in `src/Client/GunController/ActionRegistry.lua`.
- Add `"Reload"` to `Shared/Gun/Configs.ValidActions`.
- `GunStateMachine` gains `isReloading` field. `setActionActive("Reload")` rejected if `isShooting`; `setActionActive("Shoot")` rejected if `isReloading`. Serialize / resetAll updated.
- `InputRouter` binds `R` → `GunController.performAction("Reload")`.
- `ReloadAction.clientExecute` stops idle, plays reload animation, restarts idle on `track.Stopped`.
- Server's `ReloadAction.serverExecute` is a no-op that immediately triggers `CooldownReset` (via the existing `task.delay(action.cooldown, ...)` path — for Reload, cooldown is the floor value; animation length lockout is client-side).
- Client effective cooldown = `max(reloadAnimLength, ReloadCooldown)`.

---

## 6. Server Changes

### 6.1 Payload additions

**`src/Shared/Knife/PayloadValidator.lua`** — `Throw` payloads gain:

- `restOrigin: Vector3` — must be a `Vector3` value.

**`src/Shared/Gun/PayloadValidator.lua`** — `Shoot` payloads gain:

- `restOrigin: Vector3` — same.

Both validators reject if missing or of the wrong type. Distance validation (`(restOrigin - HRP.Position).Magnitude <= Configs.MaxRestOriginDistance`) happens in the action's `serverExecute` where the character/HRP is already in hand.

Stab and Reload payloads unchanged.

### 6.2 Action execution

- `ThrowAction.serverExecute` — replaces the current `handle.CFrame` origin read with `payload.restOrigin` (bounded against HRP via `MaxRestOriginDistance`). Authoritative projectile spawn uses `restOrigin` → direction. Broadcast payload to other players carries `spawnCFrame = payload.spawnCFrame` for visual consistency — server validates that `spawnCFrame.Position` is within `MaxRestOriginDistance` of HRP (same bound as `restOrigin`); if it fails validation, the server falls back to `CFrame.new(restOrigin)` for the broadcast rather than rejecting the whole throw.
- `ShootAction.serverExecute` — replaces `shootPoint.WorldPosition` with `payload.restOrigin`. Existing `MAX_SHOOT_ORIGIN_DISTANCE` check stays. Direction/raycast logic unchanged.
- `StabAction.serverExecute` — new implementation per §5.2.
- `ReloadAction.serverExecute` — no-op; existing cooldown plumbing returns `CooldownReset`.

### 6.3 Rate limiting

Unchanged. The floor values in Configs remain the authoritative upper bound on action frequency. Clients with longer animations slow themselves below the floor naturally.

---

## 7. Cancellation

Single `cancelPending()` helper per controller (`KnifeController`, `GunController`) that:

- **Bumps `pendingActionGeneration`** — any in-flight marker waiter or delay timer that fires afterward self-aborts via the generation check (§4.5).
- Cancels the release-marker waiter (flag + `task.cancel` on fallback and hard-timeout timers).
- Calls `AnimationController.stopCurrent()` — kills whatever animation is active (action *or* idle).
- Clears `pendingAction = nil`.
- Calls `stateMachine.resetAll(...)`.
- Clears `safetyTimeoutThread`.
- For gun controller: re-plays idle if the weapon is still equipped and the round is still active (so the player isn't left pose-less).

Triggers that call `cancelPending()`:

- `onPlayerDied` (existing path; extended).
- `onKnifeUnequipped` / `onGunUnequipped` (existing; extended).
- `ClientEventBus:Connect("RoundStateChanged", ...)` — new listener on both controllers. Any state other than `RoundActive` cancels.
- Incoming `StateOverride` payload.

The hard timeout on each pending action (`releaseTime + ReleaseTimeoutBuffer`) is the last-resort safety net that prevents a stuck animation from permanently locking the state machine.

---

## 8. Files Touched

### New
- `src/Shared/Animations/AnimationType.lua`
- `src/Shared/Animations/Configs.lua`
- `src/Shared/Animations/AnimationProfile.lua`
- `src/Client/GunController/Actions/ReloadAction.lua`
- `src/Server/GunService/Actions/ReloadAction.lua`

### Modified
- `src/Client/AnimationController.lua` — richer handle type, `playLooped`, `playChain`, `preloadProfile`, marker listener, length cache.
- `src/Shared/Knife/Configs.lua` — `AnimationProfiles` table; remove `StabAnimationId`, `ThrowAnimationId`.
- `src/Shared/Gun/Configs.lua` — `AnimationProfiles` table; remove `ShootAnimationId`; add `ReloadCooldown`; add `"Reload"` to `ValidActions`.
- `src/Shared/Knife/PayloadValidator.lua` — accept `restOrigin` on Throw.
- `src/Shared/Gun/PayloadValidator.lua` — accept `restOrigin` on Shoot.
- `src/Shared/Gun/GunStateMachine.lua` — `isReloading` field + transition rules.
- `src/Shared/Gun/Types.lua` — `isReloading` in type.
- `src/Client/KnifeController/init.lua` — windup/release scheduling, rest offset capture, cancelPending, round-state listener.
- `src/Client/GunController/init.lua` — windup/release scheduling, rest offset capture, idle lifecycle, cancelPending, round-state listener.
- `src/Client/KnifeController/Actions/ThrowAction.lua` — release-driven projectile spawn (move spawn from clientExecute into release callback); use animated `spawnCFrame` + rest-direction.
- `src/Client/KnifeController/Actions/StabAction.lua` — trim to animation-only.
- `src/Client/GunController/Actions/ShootAction.lua` — chain lead-in + shoot, release-driven remote dispatch.
- `src/Client/GunController/ActionRegistry.lua` — register Reload.
- `src/Client/InputRouter/Configs.lua` + `src/Client/InputRouter/executor.client.lua` — bind `R` → Reload.
- `src/Server/KnifeService/Actions/ThrowAction.lua` — consume `restOrigin`.
- `src/Server/KnifeService/Actions/StabAction.lua` — real hitbox Touched implementation during animation window.
- `src/Server/GunService/Actions/ShootAction.lua` — consume `restOrigin`.
- `src/Server/GunService/ActionRegistry.lua` — register Reload.

---

## 9. Out of Scope

- AirSpin animation on the flying knife projectile — would require rigging the Knife Tool into a Model with AnimationController; deferred.
- Ammo / magazine system — reload is cosmetic only.
- Rapid-fire lead-in skip — shoot chain always plays both animations for now.
- Knife idle, stab animation, rifle/shotgun variants — profile entries exist and will be populated when authored; no code changes needed to accept them.
- Unit tests — per project convention, integration tests only. New integration tests belong at the controller + service boundary.

---

## 10. Open Questions

None at time of writing. All decisions locked in Q1–Q7 plus the origin-handling and cooldown clarifications.
