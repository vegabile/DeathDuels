# Concrete Powers — Design Spec

**Date:** 2026-04-17
**Status:** Approved for planning
**Scope:** Thirteen concrete `Power` modules covering Movement, Combat Buffs, Defense, Utility, and Mind Games, plus a minimal client-side dispatcher for per-player visual effects. Plugs into the existing PowerService framework (`docs/superpowers/specs/2026-04-16-powers-system-design.md`).

## 1. Goal & Non-Goals

### Goal

Ship the full set of 13 powers listed below, each as a self-contained `Power` module whose `Execute` owns its entire lifecycle (application, duration, cleanup). Cross-service coordination is expressed through player attributes — nothing else. Visual effects targeting a single viewer (Reveal highlight on activator, Blinding overlay on victim) ride a single new shared remote dispatched by a tiny client controller.

### Non-Goals

- **No new services/modules for buffs, damage interception, or effect management.** Each power is self-contained in its `Execute`; cross-service coupling is the `SetAttribute`/`GetAttribute` pair.
- **No stacking buffs.** A player has exactly one equipped power (`_equippedPower`), so only one buff is ever active at a time.
- **No client-side prediction of powers.** Activation is server-authoritative (unchanged from v1 spec); the new `PowerController` only receives broadcast effect orders from the server.
- **No tuning UI / loadout picker.** Power selection still flows in via `TeleportMetadataService.GetLoadout(...).Power`.
- **No telemetry / analytics.** `Execute` returns `()`.

## 2. Power List

| Category | Power | Cooldown | Duration | Core mechanic |
|---|---|---|---|---|
| Movement | **Sprint** | 10 s | 2 s | `Humanoid.WalkSpeed *= 1.5`, restore on timer |
| Movement | **Dash** | 8 s | 0.3 s | `LinearVelocity` attachment in `HRP.CFrame.LookVector * 100`; sets `CombatDisabled` during; both cleared on timer |
| Movement | **Adrenaline** | 20 s | 5 s | WalkSpeed ×1.3 + `KnifeCooldownMult` = 0.7 + `GunCooldownMult` = 0.7 |
| Movement | **Launch** | 8 s | 3 s | `Humanoid.JumpPower *= 2`, set `Humanoid.Jump = true` once; restore on timer |
| Combat buff | **Quick Draw** | 15 s | 5 s | `KnifeCooldownMult` = 0.5 + `GunCooldownMult` = 0.5 |
| Combat buff | **Knife Speed Boost** | 15 s | 5 s | `KnifeCooldownMult` = 0.74 |
| Combat buff | **Weapon Buff** | 20 s | 5 s | `KnifeCooldownMult` = 0.74 + `GunCooldownMult` = 0.69 |
| Defense | **Shield Pulse** | 15 s | 2 s | `ShieldActive = true`; weapon services skip `TakeDamage` and clear the flag on first hit; timer clears it if unused |
| Defense | **Ghost** | 20 s | 4 s | Set `Transparency = 1` on all character `BasePart`/`Decal`; restore on timer or on `Humanoid.Died` |
| Utility | **Reveal** | 15 s | 4 s | Pick random alive enemy; `PowerBroadcast` → activator client → spawn `Highlight` with `Adornee = enemy.Character`, destroy on timer |
| Mind game | **Fake Clone** | 20 s | 8 s | Server-side `character:Clone()` parented to workspace, stripped of scripts, placed at HRP + side offset; `Debris:AddItem(clone, 8)` |
| Mind game | **Smoke Screen** | 20 s | 6 s | Spawn one anchored invisible `Part` at `HRP.Position + LookVector * 8` with `ParticleEmitter` smoke children; `Debris:AddItem(part, 6)` |
| Mind game | **Blinding** | 15 s | 3 s blind | `Instance.new("Part")` (Ball, `CanCollide=false`), `AssemblyLinearVelocity = aimDir * 120`; aim-assisted to nearest alive enemy within 30° cone of `HRP.LookVector` (fallback: straight forward); `Touched` → if victim, `PowerBroadcast` → victim client → 3 s white semi-opaque `ScreenGui` overlay |

## 3. Shared Infrastructure

### 3.1 Player attributes — the coupling surface

Powers `SetAttribute` on the `Player`; weapon services `GetAttribute` when computing state. Values default to `nil` (read as multiplier `1` / flag `false`). Each `Execute` **always** schedules a `task.delay` that clears its own attributes.

| Attribute | Type | Semantics |
|---|---|---|
| `CombatDisabled` | `boolean?` | When truthy, weapon services reject action with `StateOverride` |
| `ShieldActive` | `boolean?` | When truthy, weapon services skip `TakeDamage` on this victim and clear the flag |
| `KnifeCooldownMult` | `number?` | Multiplier (< 1 = faster) applied to knife action cooldown |
| `GunCooldownMult` | `number?` | Multiplier (< 1 = faster) applied to gun action cooldown |

No stacking logic. Because `_equippedPower` is single-choice, no two powers that write the same attribute can ever be active on the same player simultaneously. `task.delay` always sets the attribute back to `nil` (never back to `1` — nil is the canonical "no buff" state).

### 3.2 Broadcast remote — `PowerBroadcast`

Single shared `RemoteEvent` created by `executor.server.lua` at startup. Server calls `NetworkRouter:Call("PowerBroadcast", targetPlayer, envelope)`. Client `PowerController` listens and dispatches on `envelope.effectType`.

Envelope shapes:

```lua
{ effectType = "Reveal", targetCharacter = Model, durationSec = 4 }
{ effectType = "Blind",  durationSec = 3 }
```

Unknown `effectType` → `warn` + drop.

### 3.3 Client `PowerController`

`src/Client/PowerController/init.lua` owns one `NetworkRouter:Listen("PowerBroadcast", ...)` connection. Routes on `effectType` to handlers in `Effects/`. No state, no input, no prediction, no outgoing traffic.

- `Effects/Reveal.lua` — `apply(envelope)`: creates a `Highlight` locally, `Adornee = envelope.targetCharacter`, parents to `workspace`, `Debris:AddItem(highlight, durationSec)`. Re-applying while one is live replaces it.
- `Effects/Blind.lua` — `apply(envelope)`: creates a `ScreenGui` with one full-screen `Frame` (`BackgroundColor3 = Color3.new(1,1,1)`, `BackgroundTransparency = 0.1`), parents under `LocalPlayer.PlayerGui`, `Debris:AddItem(gui, durationSec)`.

`executor.client.lua` just requires the dispatcher at startup.

Per CLAUDE.md: **no `Instance.new` for UI**. The Blind overlay violates that rule if implemented naively. Resolution: the overlay `ScreenGui` + `Frame` is pre-built in Studio under `StarterGui.PowerOverlays.BlindOverlay` (set `Enabled = false` by default). `Effects/Blind.lua` clones it on demand, sets `Enabled = true`, and `Debris:AddItem` destroys the clone. The Highlight in `Effects/Reveal.lua` is a Roblox 3D adornment, not a UI element, so `Instance.new("Highlight")` is permitted.

### 3.4 Weapon service touch-points

**Only** these lines are modified; no refactors.

`src/Server/KnifeService/init.lua` — in `_handleActionRequest`, immediately after the `hasKnifeEquipped` check:

```lua
if player:GetAttribute("CombatDisabled") then
    warn(`[KNIFE] CombatDisabled on {player.Name}`)
    KnifeService._sendStateOverride(player, state, payload.sequenceId)
    return
end
```

In the same function, when consulting `action.cooldown` for the rate-limit check and the `task.delay`, multiply by the mult:

```lua
local mult = player:GetAttribute("KnifeCooldownMult") or 1
local effectiveCooldown = action.cooldown * mult
--// use effectiveCooldown for both the rate-limit comparison and task.delay
```

`src/Server/GunService/init.lua` — identical pair of edits, reading `GunCooldownMult`.

`src/Server/KnifeService/Actions/ThrowAction.lua` — inside the `KnifeProjectileHandler.spawnProjectile` callback, before `humanoid:SetAttribute("LastDamageSource", ...)`:

```lua
if hitPlayer:GetAttribute("ShieldActive") then
    hitPlayer:SetAttribute("ShieldActive", nil)
    knifeTrace(`ShieldActive absorbed hit on {hitPlayer.Name}`)
    return   --// skip damage + skip hit-confirm broadcast
end
```

`src/Server/GunService/Actions/ShootAction.lua` — identical guard inside the hit branch, before `TakeDamage`.

(Stab hit detection flows through the same place in `KnifeService` as throw — single guard covers both.)

### 3.5 File layout

**New:**

```
src/Server/PowerService/Powers/
    Sprint.lua
    Dash.lua
    Adrenaline.lua
    Launch.lua
    QuickDraw.lua
    KnifeSpeedBoost.lua
    WeaponBuff.lua
    ShieldPulse.lua
    Ghost.lua
    Reveal.lua
    FakeClone.lua
    SmokeScreen.lua
    Blinding.lua
    integration_powers.test.lua

src/Client/PowerController/
    init.lua
    executor.client.lua
    Effects/
        Reveal.lua
        Blind.lua
```

**Modified:**

- `src/Server/PowerService/Configs.lua` — add `POWERS`, `BROADCAST_REMOTE`, `EFFECT_TYPES`
- `src/Server/PowerService/PowerRegistry.lua` — require all 13 power modules, pass to `createRegistry`
- `src/Server/PowerService/executor.server.lua` — add `NetworkRouter:CreateRemoteEvent("PowerBroadcast")` at startup
- `src/Server/KnifeService/init.lua` — CombatDisabled + KnifeCooldownMult guards
- `src/Server/KnifeService/Actions/ThrowAction.lua` — ShieldActive guard
- `src/Server/GunService/init.lua` — CombatDisabled + GunCooldownMult guards
- `src/Server/GunService/Actions/ShootAction.lua` — ShieldActive guard

Pre-built UI required in Studio: `StarterGui.PowerOverlays.BlindOverlay` (`ScreenGui` + child `Frame` covering the screen, `Enabled = false`).

## 4. Configs

Extends `src/Server/PowerService/Configs.lua`:

```lua
return {
    DEBOUNCE = 0.05,

    POWERS = {
        Sprint          = { cooldown = 10, durationSec = 2,   speedMult = 1.5 },
        Dash            = { cooldown = 8,  durationSec = 0.3, impulseSpeed = 100 },
        Adrenaline      = { cooldown = 20, durationSec = 5,   speedMult = 1.3, cooldownMult = 0.7 },
        Launch          = { cooldown = 8,  durationSec = 3,   jumpPowerMult = 2.0 },
        QuickDraw       = { cooldown = 15, durationSec = 5,   cooldownMult = 0.5 },
        KnifeSpeedBoost = { cooldown = 15, durationSec = 5,   knifeCooldownMult = 0.74 },
        WeaponBuff      = { cooldown = 20, durationSec = 5,   knifeCooldownMult = 0.74, gunCooldownMult = 0.69 },
        ShieldPulse     = { cooldown = 15, durationSec = 2 },
        Ghost           = { cooldown = 20, durationSec = 4 },
        Reveal          = { cooldown = 15, durationSec = 4 },
        FakeClone       = { cooldown = 20, durationSec = 8,   spawnOffset = 3 },
        SmokeScreen     = { cooldown = 20, durationSec = 6,   spawnForward = 8 },
        Blinding        = {
            cooldown = 15,
            blindDurationSec = 3,
            projectileSpeed = 120,
            projectileLifetime = 3,
            aimAssistCone = math.rad(30),
        },
    },

    BROADCAST_REMOTE = "PowerBroadcast",

    EFFECT_TYPES = {
        Reveal = "Reveal",
        Blind  = "Blind",
    },
}
```

Each power reads only its own sub-table: `local cfg = Configs.POWERS.Sprint`. No magic numbers elsewhere.

## 5. Per-Power `Execute` Sketches

Every power follows this shape:

```lua
local Power = {}
Power.name = "sprint"   --// lowercase, registry key
Power.cooldown = Configs.POWERS.Sprint.cooldown

function Power.validatePayload(payload)
    if type(payload) ~= "table" then return false, Reasons.InvalidTarget end
    return true, nil
end

function Power:Execute(player, _payload)
    --// gate character/humanoid/HRP as needed; warn + return on miss
    --// apply effect
    --// task.delay(duration, ...) to revert
end
```

Notes on individual powers:

- **Sprint / Launch** — guard `char`, `hum`. Snapshot `baseWalkSpeed` / `baseJumpPower` before mutating. Revert handler re-checks `hum and hum.Parent` before writing.
- **Dash** — guard `char`, `hum`, `hrp`. Create an `Attachment` on HRP and a `LinearVelocity` parented to HRP with `VectorVelocity = hrp.CFrame.LookVector * impulseSpeed`, `ForceLimitsEnabled = false`, `MaxForce = math.huge`. Set `CombatDisabled`. `task.delay(0.3, ...)` destroys the LinearVelocity + Attachment and clears `CombatDisabled`.
- **Adrenaline** — the only "combo" power: writes both speed and cooldown multiplier attributes. Revert timer clears all three (`KnifeCooldownMult`, `GunCooldownMult`, restored WalkSpeed).
- **QuickDraw / KnifeSpeedBoost / WeaponBuff** — attribute-only, no character mutation. Revert timer clears the attributes.
- **ShieldPulse** — set `ShieldActive = true`. `task.delay(2, ...)` clears it (idempotent: weapon service may have already cleared it on first hit).
- **Ghost** — walk `char:GetDescendants()`; for each `BasePart` (covers `MeshPart`/`Part`) and each `Decal`, store the original `Transparency` in a local table keyed by Instance, then set `Transparency = 1`. Also hide the nameplate: `hum.NameDisplayDistance = 0` and `hum.HealthDisplayDistance = 0` (snapshot both). Revert walks the stored table, writing back only when the Instance still has `Parent`. Guards: connect `hum.Died:Connect(revert)` and `task.delay(duration, revert)` — whichever fires first wins (idempotent because revert no-ops if the table has already been drained).
- **Reveal** — iterate `Players:GetPlayers()`, filter to alive + team-opposite-of-activator (via `TeleportMetadataService.GetTeam`). If empty, `warn + return`. Else pick random, call `NetworkRouter:Call("PowerBroadcast", activator, { effectType = "Reveal", targetCharacter = target.Character, durationSec = 4 })`. No server-side cleanup needed (client `Debris:AddItem`).
- **FakeClone** — guard `char`, `hrp`. `char:Clone()`, remove every descendant `Script`/`LocalScript`. Set `clone.Humanoid.NameDisplayDistance = 0` if it has a nametag to hide; keep R15 rig and `Animator` so idle breathing replicates. `clone.Parent = workspace`. `clone:PivotTo(hrp.CFrame * CFrame.new(3, 0, 0))`. `Debris:AddItem(clone, 8)`.
- **SmokeScreen** — one anchored, `CanCollide = false`, `Transparency = 1` `Part` at `hrp.Position + LookVector * 8`. Child it with `ParticleEmitter`s configured for dark smoke (`Rate = 40`, `Lifetime = NumberRange.new(2, 4)`, `Size = NumberSequence.new(8)`, `Color = ColorSequence.new(Color3.new(0.1, 0.1, 0.1))`, `Transparency` fade-in/out `NumberSequence`). `Instance.new("ParticleEmitter")` is permitted — the CLAUDE.md rule bans `Instance.new` for *UI* (ScreenGui / Frame / etc.); ParticleEmitter is a 3D-world instance. `Debris:AddItem(part, 6)`.
- **Blinding** — enumerate alive enemy players; for each, compute angle between `hrp.CFrame.LookVector` and `(enemy.HRP.Position - hrp.Position).Unit`; pick the smallest if under `aimAssistCone`. Fallback: `hrp.CFrame.LookVector`. Spawn `Instance.new("Part")`: Ball shape, size 2, `CanCollide = false`, `Anchored = false`, `Massless = true`. Set `AssemblyLinearVelocity = direction * 120`. Connect `Touched` — if hit is a part under a player's character ≠ activator, fire `PowerBroadcast` to that player with `effectType = "Blind"`, `durationSec = 3`, destroy projectile. `Debris:AddItem(projectile, 3)` as lifetime cap.

All `Execute` bodies use `warn + return` on any missing prerequisite (character, humanoid, HRP). Never silent.

## 6. Validation

### 6.1 Payload validation

All 13 powers accept **empty payload** (`payload = {}`). `validatePayload` rejects non-table; server derives aim, direction, and target from character state. Removes a client-spoof surface at zero UX cost (aim assist is implicit in all targeted powers).

### 6.2 Broadcast envelope validation (client-side `PowerController`)

```lua
if type(envelope) ~= "table" then warn(...); return end
if type(envelope.effectType) ~= "string" then warn(...); return end
local handler = effectHandlers[envelope.effectType]
if not handler then warn(`unknown effectType: {envelope.effectType}`); return end
handler(envelope)
```

Each effect handler does its own shape check:

- `Reveal`: `typeof(envelope.targetCharacter) == "Instance"` and `envelope.targetCharacter:IsA("Model")` and `envelope.targetCharacter.Parent ~= nil`; `type(envelope.durationSec) == "number"` and `envelope.durationSec > 0`
- `Blind`: `type(envelope.durationSec) == "number"` and `envelope.durationSec > 0`

## 7. Testing

Per project policy: integration tests only, no unit tests. One new suite.

`src/Server/PowerService/Powers/integration_powers.test.lua` — runs via `mcp__robloxstudio__execute_luau`. Uses mock players (same fixture pattern as `integration_power_system.test.lua`) and real `Humanoid`/`HumanoidRootPart` for powers that need them (spawned under a `Folder` in workspace; cleaned up between cases).

For each of the 13 powers, one case that:

1. Constructs a `PowerService` instance with the correct loadout
2. Calls `:Activate(powerName, {})`
3. Asserts the observable mid-duration state (attribute set, WalkSpeed elevated, part exists, etc.)
4. `task.wait(durationSec + 0.1)`
5. Asserts the post-duration cleanup (attribute nil, WalkSpeed restored, part gone, etc.)

Special-case assertions:

| Power | Mid-duration check | Post-duration check |
|---|---|---|
| Sprint | `hum.WalkSpeed == base * 1.5` | `hum.WalkSpeed == base` |
| Dash | `player:GetAttribute("CombatDisabled") == true`; a `LinearVelocity` exists under HRP | attribute nil; LinearVelocity gone |
| Adrenaline | 3 attributes set | 3 attributes cleared |
| Launch | `hum.JumpPower == base * 2` | `hum.JumpPower == base` |
| QuickDraw / KnifeSpeedBoost / WeaponBuff | correct `*CooldownMult` attributes | attributes cleared |
| ShieldPulse | `ShieldActive == true` | `ShieldActive == nil` |
| Ghost | every BasePart `Transparency == 1` | all BaseParts' original transparency restored |
| Reveal | `PowerBroadcast` received a `{effectType="Reveal", ...}` call — test monkey-patches `NetworkRouter.Call` with a capturing wrapper before `:Activate`, restores it after, asserts the captured envelope shape | n/a (client owns cleanup) |
| FakeClone | a cloned Model parented to workspace with the same name | clone removed (`Debris`) |
| SmokeScreen | smoke Part parented to workspace | smoke Part removed |
| Blinding | projectile Part exists with nonzero `AssemblyLinearVelocity` | projectile removed (lifetime cap) |

**Weapon-service touch-points** — one additional test file mutates power-relevant attributes directly and calls into KnifeService/GunService action handlers to prove:

- `CombatDisabled = true` → action rejected with StateOverride
- `KnifeCooldownMult = 0.5` → rate-limit uses halved cooldown (second call accepted after half the normal wait)
- `ShieldActive = true` → `humanoid:TakeDamage` not called on throw/shoot hit; attribute cleared by the hit

File: `src/Server/PowerService/integration_weapon_touchpoints.test.lua`. Reuses the existing knife/gun service state fixtures.

**Client dispatcher** — no integration test. Manual verification in a live session: fire `PowerBroadcast` from a server shell, confirm Highlight/ScreenGui appears and is destroyed.

**Out of scope:**

- End-to-end flows (client → server remote → Execute → broadcast → client effect). Covered in manual session testing.
- Visual quality of smoke particles and blind overlay. Designer tuning, not automated.
- Balance (cooldown/duration values). Live-play iteration, not spec concern.

## 8. Constraints Honored

- **Server-authoritative.** Every power's `Execute` runs server-side; client only receives broadcast visual orders.
- **One file, one responsibility.** Each power is its own file; each effect handler is its own file; the dispatcher is separate from the executor.
- **No silent returns.** Every guard (`char`, `hum`, `hrp`, empty enemy list, unknown effectType) ends in `warn + return`.
- **No `Instance.new` for UI.** Blind overlay is pre-built in `StarterGui`, cloned on demand. Highlight (not UI), ParticleEmitter (not UI), and gameplay Parts use `Instance.new` freely.
- **Comments use `--//`.** Obvious ones omitted.
- **Configuration in one place.** `Configs.POWERS` is the only source of per-power constants.
- **Depend on contracts, not implementations.** Weapon services read attributes; they don't know who set them. Powers set attributes; they don't know who reads them.

## 9. Open / Deferred

- **Client-side preview/audio cues** (activation sound, self-visual for Ghost that lets the player track themselves). Not required for functional parity with the brief. Can land as a follow-up that only touches `Effects/` + adds effect types.
- **Mobile input for power activation.** Still covered by the existing input design work; this spec does not ship a keybinding. Assumption: caller (likely a future `PowerInput` controller) fires the `PowerAction_{UserId}` remote.
- **Balance pass.** Values in §4 are reasonable first-pass defaults; tuning is expected.
- **Anti-spam on `PowerBroadcast`.** Server-originated only — no client can spoof. No rate-limit needed.
