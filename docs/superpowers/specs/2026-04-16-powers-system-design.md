# Powers System — Design Spec

**Date:** 2026-04-16
**Status:** Approved for planning
**Scope:** Server-authoritative, OOP, per-player power activation pipeline. Plumbing only — no concrete Powers ship in this work.

## 1. Goal & Non-Goals

### Goal

Provide a minimal, server-authoritative system that answers one question per request: **did activation start, and if not, why not?** Once activation is accepted, the Power module owns everything downstream (execution, effects, damage, animation, projectiles). PowerService does not track or care what happens after handoff.

### Non-Goals

- No execution lifecycle tracking (no "power ended", no mid-flight result, no cancel).
- No concrete Power modules (Dash, Fireball, etc.). The `Powers/` folder ships empty.
- No client-side controller, prediction, or UI. Client integration is a follow-up.
- No post-handoff side effects (telemetry, broadcasts, analytics).

## 2. File Layout

```
src/Server/PowerService/
    init.lua              --// PowerService class + module-local map + .new/.Get
    executor.server.lua   --// PlayerAdded/PlayerRemoving, Humanoid.Died hook, remote listener
    Configs.lua           --// DEBOUNCE = 0.05, DEBUG_MODE
    Types.lua             --// internal instance shape (re-exports shared types)
    PowerRegistry.lua     --// built via ActionRegistryFactory over Powers/*
    Powers/               --// empty; powers added in a later feature

src/Shared/Power/
    Types.lua             --// Power, PowerResult, PowerFailReason, envelope shapes
    PowerFailReason.lua   --// frozen enum table
    PayloadValidator.lua  --// validates client→server envelope, returns sanitized sequenceId

docs/superpowers/specs/2026-04-16-powers-system-design.md   --// this file
```

Follows the existing `KnifeService` / `GunService` convention: `init.lua` owns state; `executor.server.lua` owns Roblox event wiring; `Types` / `Configs` / `Registry` are siblings. Reuses `ActionRegistryFactory` — no new registry abstraction.

## 3. Contracts

### 3.1 `PowerFailReason` enum (`Shared/Power/PowerFailReason.lua`)

```lua
return table.freeze({
    UnknownPower  = "UnknownPower",
    OnCooldown    = "OnCooldown",
    Debounced     = "Debounced",
    Locked        = "Locked",        --// reserved; unused in v1 (lock == cooldown)
    InvalidState  = "InvalidState",
    InvalidTarget = "InvalidTarget",
    NoPermission  = "NoPermission",
})
```

`Locked` is reserved for future external-lock work (stuns, silence, etc.). Not produced in v1.

### 3.2 Shared types (`Shared/Power/Types.lua`)

```lua
export type PowerFailReason = "UnknownPower" | "OnCooldown" | "Debounced"
                            | "Locked" | "InvalidState" | "InvalidTarget" | "NoPermission"

export type PowerResult = { success: boolean, reason: PowerFailReason? }

export type Power = {
    name:            string,                                      --// lowercase; registry key
    cooldown:        number,                                      --// seconds
    validatePayload: (payload: any) -> (boolean, PowerFailReason?),
    Execute:         (self: Power, player: Player, payload: any) -> (),
}

export type ActivateRequest  = { powerName: string, payload: any, sequenceId: number }
export type ActivateResponse = { sequenceId: number, result: PowerResult }
```

`Power.Execute` uses colon syntax (per CLAUDE.md rule + the spec). `validatePayload` is a plain function — pure, no `self`.

### 3.3 PowerService API (`Server/PowerService/init.lua`)

```lua
PowerService.new(player: Player): PowerService
PowerService.Get(player: Player): PowerService?

powerService:Activate(powerName: string, payload: any): PowerResult
powerService:Destroy()
```

Module-local hash table `instancesByPlayer: { [Player]: PowerService }` holds the instances. No separate `PowerManager`.

### 3.4 Instance fields

```lua
self.player            : Player
self._equippedPower    : Power?                   --// resolved once in .new
self._cooldowns        : { [string]: number }     --// power.name → expiry tick
self._lastAttempt      : { [string]: number }     --// power.name → last :Activate call tick
```

No lock field — lock == cooldown. If a future feature needs an external lock, it becomes a new field + new `InvalidState` gate, not an API shift.

## 4. Loadout Resolution

`TeleportDataValidator` currently fills `loadouts[userId] = { knifeName, gunName }`. The field `Power` (capital P, string) is expected on the loadout going forward. Resolution happens exactly once, in `PowerService.new`:

1. `TeleportMetadataService.GetLoadout(player.UserId)` → loadout table.
2. If loadout or `loadout.Power` missing → `warn` + leave `_equippedPower = nil`.
3. Else `PowerRegistry.getPower(loadout.Power:lower())` → on nil, `warn` + leave `_equippedPower = nil`.
4. Otherwise cache resolved Power on `_equippedPower`.

When `_equippedPower` is `nil`, every `:Activate` call returns `{success = false, reason = NoPermission}`. No crashes, no recovery.

No default Power. A missing `.Power` is a bug upstream (matchmaking / teleport data), logged via `warn` and absorbed cleanly so the match can continue.

`TeleportDataValidator` is **not** modified in this work. Powers flow through the existing `loadouts` table untouched — no validator-level defaulting, no added constants. If `.Power` is absent, PowerService handles it gracefully.

## 5. `:Activate` Flow (authoritative)

```lua
function PowerService:Activate(powerName: string, payload: any): PowerResult
    local now = tick()

    --// 1. Resolve requested power
    local requested = PowerRegistry.getPower(powerName:lower())
    if not requested then
        return { success = false, reason = Reasons.UnknownPower }
    end

    --// 2. Permission: requested must equal equipped
    if self._equippedPower == nil or self._equippedPower.name ~= requested.name then
        return { success = false, reason = Reasons.NoPermission }
    end

    --// 3. External state gates
    if not self.player:IsDescendantOf(Players) then
        return { success = false, reason = Reasons.InvalidState }
    end
    if currentRoundState ~= RoundConfigs.GAME_STATES.RoundActive then
        return { success = false, reason = Reasons.InvalidState }
    end
    local char = self.player.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return { success = false, reason = Reasons.InvalidState }
    end

    --// 4. Debounce (stamp runs on every attempt below this line)
    local lastAttempt = self._lastAttempt[requested.name] or 0
    if (now - lastAttempt) < Configs.DEBOUNCE then
        self._lastAttempt[requested.name] = now
        return { success = false, reason = Reasons.Debounced }
    end

    --// 5. Payload validation
    local ok, reason = requested.validatePayload(payload)
    if not ok then
        self._lastAttempt[requested.name] = now
        return { success = false, reason = reason or Reasons.InvalidTarget }
    end

    --// 6. Cooldown check
    local expiry = self._cooldowns[requested.name] or 0
    if now < expiry then
        self._lastAttempt[requested.name] = now
        return { success = false, reason = Reasons.OnCooldown }
    end

    --// 7. Lock == cooldown: start cooldown BEFORE handoff
    self._cooldowns[requested.name]  = now + requested.cooldown
    self._lastAttempt[requested.name] = now

    --// 8. Handoff — fire-and-forget, no pcall
    requested:Execute(self.player, payload)

    return { success = true, reason = nil }
end
```

**Semantics:**

- Gate order matches the spec exactly: resolve → exists → permission → state → debounce → payload → cooldown → lock/cooldown-start → handoff.
- `_lastAttempt` is stamped on **every attempt past gate 3** (state gates are free to spam; gates 4–7 all stamp). This is what actually stops remote spam — otherwise a failing call never advances the debounce window.
- `Execute` is called synchronously, unpcalled. A throwing power surfaces loudly — matches the "never silent-fail" rule.
- No post-handoff work: no events, no broadcasts, no telemetry.

## 6. Cooldown & Debounce

- **Cooldown:** per-player, per-power. Stored in `_cooldowns[power.name]` as an absolute expiry tick. Starts immediately after validation passes (step 7), before `Execute`. No separate clear — the next `:Activate` simply sees `now >= expiry`.
- **Debounce:** `Configs.DEBOUNCE = 0.05` (50 ms). Per-player, per-power. Fixed value — no per-Power override in v1. Stamped on every attempt that reaches gate 4 or beyond, pass or fail.

## 7. Executor (`Server/PowerService/executor.server.lua`)

**Responsibilities** (Roblox event wiring only):

- On startup and `Players.PlayerAdded`:
  1. `NetworkRouter:CreateRemoteEvent("PowerAction_{UserId}")`.
  2. `PowerService.new(player)`.
  3. `NetworkRouter:Listen(remoteName, handler)` — see handler below.

- On `Players.PlayerRemoving`:
  1. `PowerService.Get(player):Destroy()`.
  2. `NetworkRouter:Remove("PowerAction_{UserId}")`.

**Round-state listener** lives in `init.lua` (same pattern as `KnifeService`), not in the executor:

```lua
local currentRoundState: string = ""
ServerEventBus:Connect("RoundStateChanged", function(newState) currentRoundState = newState end)
```

### 7.1 Remote handler

```lua
local function handler(firingPlayer, envelope)
    if firingPlayer ~= player then
        warn(`[POWER] Remote spoofing: {firingPlayer.Name} on {player.Name}'s remote`)
        return
    end

    local ok, reason, sequenceId = PayloadValidator.validate(envelope)
    if not ok then
        warn(`[POWER] Malformed envelope from {player.Name}: {reason}`)
        NetworkRouter:Call(remoteName, player, {
            sequenceId = sequenceId,
            result     = { success = false, reason = reason },
        })
        return
    end

    local svc = PowerService.Get(player)
    if not svc then
        warn(`[POWER] No PowerService instance for {player.Name}`)
        return
    end

    local result = svc:Activate(envelope.powerName, envelope.payload)
    NetworkRouter:Call(remoteName, player, {
        sequenceId = envelope.sequenceId,
        result     = result,
    })
end
```

Every call from the legitimate client receives an `ActivateResponse`. Spoofed calls (`firingPlayer ~= player`) are dropped — there is no legitimate client to inform. The no-instance branch is a defensive guard that should never fire after `.new`.

## 8. PayloadValidator (`Shared/Power/PayloadValidator.lua`)

```lua
PayloadValidator.validate(envelope: any) -> (ok: boolean, reason: PowerFailReason?, sequenceId: number)
```

Returns a best-effort `sequenceId` (number ≥ 0, else `0`) as the third return — always — so the handler can echo it back to the client on rejection.

Failure mapping:

| Condition | Return |
|---|---|
| `envelope` not a table | `(false, InvalidTarget, 0)` |
| missing or non-string `powerName` | `(false, UnknownPower, sanitizedSeq)` |
| other shape issue (missing `sequenceId`, `payload` absent, etc.) | `(false, InvalidTarget, sanitizedSeq)` |
| clean | `(true, nil, sanitizedSeq)` |

Deeper per-power payload validation is `power.validatePayload`'s job, not this module's.

## 9. Registry (`Server/PowerService/PowerRegistry.lua`)

```lua
local createRegistry = require(ReplicatedStorage.ActionRegistryFactory)
--// Powers/ is empty in v1; follow-up features add entries here.
local base = createRegistry({})

local PowerRegistry = {}
function PowerRegistry.getPower(name: string) return base.getAction(name) end
return PowerRegistry
```

Thin wrapper exposes `.getPower` over the underlying registry. Keeps the domain naming clean (PowerService calls `PowerRegistry.getPower`, never `.getAction`) without forking `ActionRegistryFactory`.

## 10. Testing

Per project policy (integration tests only, no unit tests): `src/Server/PowerService/integration_power_system.test.lua`.

**Harness:**

- `TeleportMetadataService.Initialize(...)` with a handcrafted `TeleportMetadata` before each test block.
- Drive `RoundStateChanged` via `ServerEventBus` to move round state.
- Real `NetworkRouter`, real `PowerRegistry` populated with a single throwaway test-only fixture Power `{ name = "testpower", cooldown = 1, validatePayload = ..., Execute = spy }`.
- Fake `Player` table (as in `TeamState` tests): `{ UserId, Name, Character, IsDescendantOf }`.

**Cases:**

| # | Case | Expected |
|---|---|---|
| 1 | Unknown power requested | `{false, UnknownPower}` |
| 2 | Equipped mismatch | `{false, NoPermission}` |
| 3 | Player left game | `{false, InvalidState}` |
| 4 | Round not active | `{false, InvalidState}` |
| 5 | Character dead | `{false, InvalidState}` |
| 6 | Debounced | 1st `{true}`, 2nd within 50ms `{false, Debounced}` |
| 7 | Payload invalid | `{false, InvalidTarget}` |
| 8 | On cooldown | 1st `{true}`, 2nd within cooldown `{false, OnCooldown}` |
| 9 | Happy path | `{true}` + `Execute` spy called once with `(player, payload)` |
| 10 | Cooldown release | both `{true}` after waiting > cooldown |
| 11 | Destroy cleans map | `.Get(p)` returns nil after `:Destroy()` |
| 12 | Loadout missing `.Power` | `.new` warns; any `:Activate` → `{false, NoPermission}` |
| 13 | Loadout `.Power` unresolved | `.new` warns; any `:Activate` → `{false, NoPermission}` |
| 14 | `.Power` case-insensitive | `"DaSh"` resolves registry key `"dash"`; happy path works |

**Out of scope:**

- Client-side `ActivateResponse` handling.
- Spoofed remote calls (covered by `NetworkRouter` tests).
- Real Power `Execute` behavior — no real Powers ship in this work.

## 11. Constraints Honored

- Server-authoritative: client may request, never decides. Server produces the only `PowerResult`.
- Colon notation on instance methods (`:Activate`, `:Destroy`, `Power:Execute`).
- No silent returns: every rejection path produces either a `PowerResult` (to caller) or a `warn` (malformed/spoofed).
- No `Instance.new` for UI — N/A here; this is pure server.
- One file, one responsibility: registry, validator, enum, types, executor, service all split.
- Result shape fixed and minimal: `{success, reason?}`. No `data`, no `powerRef`, no metadata.
- No advanced cast lifecycle. Lock == cooldown. `Locked` enum reserved, not used.

## 12. Open / Deferred

- First concrete Power(s) — separate feature, separate spec.
- Client PowerController + input binding — separate feature.
- External lock triggers (stun, silence, ability disable) — deferred until a design case forces them. Infrastructure in place: add a field, add an `InvalidState` (or activate `Locked`) gate in step 3.
- `TeleportDataValidator` default for `.Power` — intentionally not added. Upstream owns correctness; PowerService absorbs the miss with a `warn`.
