# Ability UI Activation — Design Spec

**Date:** 2026-04-17
**Status:** Draft for review
**Scope:** Wire the existing `StarterGui.AbilityUI.Frame.Button` (TextButton) and a keybind (`F` keyboard / `ButtonX` gamepad) to fire the `PowerAction_{UserId}` remote for the player's equipped power, with a cooldown display and visibility gated on equipped + alive + `RoundActive`. No new server services; depends on the PowerService pipeline shipped by `2026-04-16-powers-system-design.md`.

## 1. Goal & Non-Goals

### Goal

Let the player activate their equipped power by pressing the on-screen `Button`, `F`, or `ButtonX`. Show the power's display name on the button, grey + disable + count down during cooldown, and hide the whole UI whenever an activation attempt would be guaranteed to fail (no power equipped, not alive, round not active).

### Non-Goals

- **No loadout picker / power chooser.** `EquippedPower` is set by `PowerService.new` from teleport metadata. Lobby UI is out of scope.
- **No client-side prediction of power effects.** Activation is server-authoritative — the client only displays cooldown feedback.
- **No stacking or queueing.** One press = one request. While waiting for the server response (or during cooldown), the button is disabled.
- **No icons.** `Button.Text` shows the power's display name. Icons are a follow-up.
- **No per-power keybinds.** A single fixed key (`F` / `ButtonX`) works for every power.
- **No settings / rebinding UI.**
- **No changes to `Effects/Reveal.lua` / `Effects/Blind.lua`** — those are defined in the concrete-powers spec and are unaffected.

## 2. File Layout

```
src/Client/PowerController/
    Input/
        init.lua           --// NEW — button + keybind + cooldown + visibility
        Configs.lua        --// NEW — client display config
    Effects/               --// already in concrete-powers spec; unchanged
    executor.client.lua    --// already in concrete-powers spec; EXTENDED
    init.lua               --// already in concrete-powers spec; unchanged

src/Client/InputRouter/
    Configs.lua            --// MODIFIED — add PowerBindings
    init.lua               --// MODIFIED — add bindPower / unbindPower

src/Shared/Power/
    Configs.lua            --// NEW — POWERS_BY_NAME lookup (client + server readable)

src/Server/PowerService/
    init.lua               --// MODIFIED — set/clear EquippedPower attribute
```

The executor extension and the `Input/` subdir ship in this work. The `Effects/` subdir and the dispatcher portion of `init.lua` are the concrete-powers spec's responsibility (not blocked by this work — either can land first).

## 3. Contracts

### 3.1 Server → client: `EquippedPower` player attribute

```
player:GetAttribute("EquippedPower") : string?
```

- Lowercase power name (matches `Power.name` registry key), e.g. `"sprint"`, `"smokescreen"`.
- Set in `PowerService.new` immediately after `_equippedPower` resolves. Cleared in `PowerService:Destroy`.
- `nil` when the loadout was malformed, unresolved, or PowerService hasn't run yet — the UI treats `nil` as "no power equipped" and hides itself.

### 3.2 Client → server: `PowerAction_{UserId}` remote

No change from the existing powers-system spec. The client fires:

```lua
NetworkRouter:Call(`PowerAction_{userId}`, {
    powerName  = equippedPowerName,   --// read from EquippedPower attribute
    payload    = {},                   --// all 13 powers accept empty payload
    sequenceId = <increment>,
})
```

Server echoes back an `ActivateResponse` envelope: `{ sequenceId, result = { success, reason? } }`.

### 3.3 Client `PowerController/Input` API

```lua
Input.init(abilityUi: ScreenGui, button: TextButton): ()
Input.destroy(): ()
```

`init` wires the internal listeners and returns immediately. `destroy` tears them down. Both are idempotent.

### 3.4 `InputRouter` additions

```lua
InputRouter.bindPower(callback: () -> ())
InputRouter.unbindPower()
```

A single unnamed action (`"PowerActivate"`), no `actionName` arg — there is only one power binding at a time. Follows the `bindWeapon` / `unbindWeapon` shape, but without the `weaponType` key because there's exactly one group.

## 4. Server Changes

### 4.1 `PowerService/init.lua`

In `PowerService.new`, immediately after the block that sets `self._equippedPower`:

```lua
if self._equippedPower then
    player:SetAttribute("EquippedPower", self._equippedPower.name)
end
```

In `PowerService:Destroy`:

```lua
self.player:SetAttribute("EquippedPower", nil)
```

No other server code reads this attribute — it exists purely as a replicated signal for the client UI. It's coherent with the buff-attribute pattern the concrete-powers spec already uses.

### 4.2 `src/Shared/Power/Configs.lua`  (new module)

Shared between client and server. Client requires from `ReplicatedStorage.Power.Configs`; server can read the same values. Holds only the UI-facing slice — gameplay-tuning fields (durations, speed multipliers, particle configs, etc.) continue to live in `src/Server/PowerService/Configs.lua` under the concrete-powers spec.

```lua
local POWERS_BY_NAME = {
    sprint          = { displayName = "Sprint",            cooldown = 10 },
    dash            = { displayName = "Dash",              cooldown = 8  },
    adrenaline      = { displayName = "Adrenaline",        cooldown = 20 },
    launch          = { displayName = "Launch",            cooldown = 8  },
    quickdraw       = { displayName = "Quick Draw",        cooldown = 15 },
    knifespeedboost = { displayName = "Knife Speed Boost", cooldown = 15 },
    weaponbuff      = { displayName = "Weapon Buff",       cooldown = 20 },
    shieldpulse     = { displayName = "Shield Pulse",      cooldown = 15 },
    ghost           = { displayName = "Ghost",             cooldown = 20 },
    reveal          = { displayName = "Reveal",            cooldown = 15 },
    fakeclone       = { displayName = "Fake Clone",        cooldown = 20 },
    smokescreen     = { displayName = "Smoke Screen",      cooldown = 20 },
    blinding        = { displayName = "Blinding",          cooldown = 15 },
}

return {
    POWERS_BY_NAME = POWERS_BY_NAME,
}
```

The table key **is** the registry name — it must match the `Power.name` set in each concrete Power module (which concrete-powers ships). A mismatch is caught the first time the client receives the attribute (unknown-name branch in §8).

Cooldown duplication note: the concrete-powers spec also stores `cooldown` in its own `POWERS` table. When concrete-powers lands, its server-side `cooldown` should be sourced from this shared module (`require(ReplicatedStorage.Power.Configs).POWERS_BY_NAME[<name>].cooldown`) so the two stay in lockstep. Until then, the author of concrete-powers keeps them in sync manually.

## 5. Client: `PowerController/Input/init.lua`

### 5.1 Internal state

```lua
local state = {
    abilityUi       = nil,          --// ScreenGui (injected)
    button          = nil,          --// TextButton (injected)
    powerName       = nil,          --// lowercase, mirrors EquippedPower attr
    powerEntry      = nil,          --// resolved SharedPowerConfigs.POWERS_BY_NAME entry
    roundActive     = false,        --// tracked via ClientEventBus RoundUpdate (snapshot.state)
    alive           = false,        --// tracked via CharacterAdded + Humanoid.Died
    pendingResponse = false,        --// true between press and ActivateResponse
    pendingTimeout  = nil,          --// safety thread; clears pendingResponse if server never replies
    cooldownUntil   = 0,            --// os.clock() absolute expiry
    cooldownThread  = nil,          --// active update thread
    sequenceId      = 0,            --// last-fired sequence
}
```

### 5.2 Listener wiring (all hooked in `init`)

| Signal | Handler |
|---|---|
| `localPlayer:GetAttributeChangedSignal("EquippedPower")` | re-read attr, resolve `powerEntry`, refresh visibility + button text |
| `ClientEventBus:Connect("RoundUpdate", snapshot)` | `state.roundActive = snapshot.state == "RoundActive"`, refresh visibility |
| `localPlayer.CharacterAdded` | connect `Humanoid.Died`, set `alive = true`, refresh |
| `Humanoid.Died` | set `alive = false`, cancel cooldown thread, refresh |
| `button.MouseButton1Click` | call `onActivatePressed()` |
| `InputRouter.bindPower(onActivatePressed)` | on equip, see 5.4 |
| `NetworkRouter:Listen("PowerAction_{UserId}", onServerResponse)` | handle `ActivateResponse` |

`ClientEventBus` `RoundUpdate` is what `RoundController.Init` already fires on the client after receiving the server's `RoundUpdate` remote. `snapshot.state` is a string equal to one of `RoundConfigs.GAME_STATES`. The initial snapshot is also fired from `RoundController.Init` via a one-shot `NetworkRouter:Call("RoundGetSnapshot")`, so joining mid-round still populates the round-state gate correctly.

### 5.3 Visibility refresh (`refresh()`)

```lua
local visible = state.powerEntry ~= nil
    and state.roundActive
    and state.alive

state.abilityUi.Enabled = visible

if visible then
    InputRouter.bindPower(onActivatePressed)
    --// Button.Text handled by updateButtonText(), see 5.5
else
    InputRouter.unbindPower()
    cancelCooldown()
end
```

`AbilityUI.Enabled` is flipped — the UI is pre-built in `StarterGui`, nothing is constructed at runtime.

### 5.4 Press flow (`onActivatePressed`)

```lua
if not isActivatable() then return end   --// visible + not pending + not on cooldown

state.sequenceId += 1
state.pendingResponse = true
updateButtonText()   --// immediately grey/disable while we wait

--// Safety timeout: if the server response never arrives (remote dropped,
--// server crash), release pendingResponse and ungrey after one cooldown's
--// worth of buffer. Matches the KnifeController safetyTimeoutThread pattern.
if state.pendingTimeout then task.cancel(state.pendingTimeout) end
local thisSequence = state.sequenceId
state.pendingTimeout = task.delay(state.powerEntry.cooldown + Configs.PENDING_TIMEOUT_BUFFER, function()
    if state.sequenceId == thisSequence and state.pendingResponse then
        warn(`[POWER] No ActivateResponse for seq={thisSequence}; ungreying`)
        state.pendingResponse = false
        updateButtonText()
    end
end)

NetworkRouter:Call(remoteName, {
    powerName  = state.powerName,
    payload    = {},
    sequenceId = state.sequenceId,
})
```

Called from both the `MouseButton1Click` handler and the `InputRouter` keybind callback — they hit the same function, so one press = one request regardless of input source.

### 5.5 Server response (`onServerResponse`)

```lua
if type(payload) ~= "table" then return end
if type(payload.sequenceId) ~= "number" then return end
if payload.sequenceId ~= state.sequenceId then
    --// stale response (shouldn't happen given single-in-flight, but drop cleanly)
    return
end

state.pendingResponse = false
if state.pendingTimeout then
    task.cancel(state.pendingTimeout)
    state.pendingTimeout = nil
end

local result = payload.result
if type(result) ~= "table" or result.success ~= true then
    --// rejection of any kind: no cooldown, ungrey
    updateButtonText()
    return
end

--// success: start cooldown
local now = os.clock()
state.cooldownUntil = now + state.powerEntry.cooldown
startCooldownThread()
```

Rejections do **not** start a cooldown. The player can re-press immediately (up to the 50ms server debounce). If the rejection reason is `InvalidState` (dead, round ended), `refresh()` will be triggered by the character-died or round-state listener independently and hide the UI anyway.

### 5.6 Cooldown thread + button text

`startCooldownThread()` spawns a single task that loops until `os.clock() >= cooldownUntil`, calling `updateButtonText()` every `Configs.COOLDOWN_UPDATE_INTERVAL` (default `0.1s`). On exit it calls `updateButtonText()` once to restore the ready state.

```lua
local function updateButtonText()
    if not state.powerEntry then return end
    local remaining = state.cooldownUntil - os.clock()
    if state.pendingResponse or remaining > 0 then
        state.button.AutoButtonColor = false
        state.button.Active = false
        local label = state.pendingResponse
            and state.powerEntry.displayName
            or string.format("%.1fs", remaining)
        state.button.Text = label
        state.button.TextTransparency = 0.4
    else
        state.button.AutoButtonColor = true
        state.button.Active = true
        state.button.Text = state.powerEntry.displayName
        state.button.TextTransparency = 0
    end
end
```

`state.button.Active = false` blocks the `MouseButton1Click` handler from firing while disabled; the `onActivatePressed` early-return on `isActivatable()` is defense-in-depth for the keybind path (ContextActionService doesn't respect `Active`). Format `%.1fs` gives `"5.3s"`, `"0.4s"`, etc. — swapped trivially for `%.0fs` or a MOBA-style radial later.

### 5.7 Cancellation

`cancelCooldown()`:

```lua
if state.cooldownThread then
    task.cancel(state.cooldownThread)
    state.cooldownThread = nil
end
if state.pendingTimeout then
    task.cancel(state.pendingTimeout)
    state.pendingTimeout = nil
end
state.cooldownUntil = 0
state.pendingResponse = false
updateButtonText()
```

Called from death, round end, `EquippedPower` becoming `nil`, and `destroy`. Idempotent.

`Input/Configs.lua`:

```lua
return {
    COOLDOWN_UPDATE_INTERVAL = 0.1,   --// seconds between button text refreshes
    PENDING_TIMEOUT_BUFFER   = 1.0,   --// seconds added to cooldown for safety timeout
}
```

## 6. `InputRouter` Extension

### 6.1 Configs

```lua
--// appended to InputRouter/Configs.lua
PowerBindings = {
    Activate = {
        actionName  = "PowerActivate",
        keyboard    = Enum.KeyCode.F,
        gamepad     = Enum.KeyCode.ButtonX,
        touchButton = false,            --// handled by on-screen TextButton "Button"
    },
},
```

### 6.2 Functions

```lua
function InputRouter.bindPower(callback: () -> ())
    local binding = Configs.PowerBindings.Activate
    local inputs = {}
    if binding.keyboard then table.insert(inputs, binding.keyboard) end
    if binding.gamepad  then table.insert(inputs, binding.gamepad)  end

    ContextActionService:BindAction(
        binding.actionName,
        function(_, inputState)
            if inputState ~= Enum.UserInputState.Begin then return end
            callback()
        end,
        binding.touchButton,
        table.unpack(inputs)
    )
end

function InputRouter.unbindPower()
    ContextActionService:UnbindAction(Configs.PowerBindings.Activate.actionName)
end
```

Mirrors `bindWeapon` / `unbindWeapon` exactly but skips the `weaponType` lookup — there's only one power binding group.

## 7. `executor.client.lua`

The concrete-powers spec already creates this file and requires the dispatcher. Extension:

```lua
local Players  = game:GetService("Players")
local Input    = require(script.Parent.Input)
local PowerController = require(script.Parent)   --// dispatcher

PowerController.init()   --// from concrete-powers spec (Effects/ dispatcher)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilityUi = playerGui:WaitForChild("AbilityUI")
local frame     = abilityUi:WaitForChild("Frame")
local button    = frame:WaitForChild("Button")

if not button:IsA("TextButton") then
    warn(`[POWER] AbilityUI.Frame.Button is {button.ClassName}, expected TextButton`)
    return
end

Input.init(abilityUi, button)
```

Follows the CLAUDE.md rule that UI must be passed in as a parameter. The executor is the *only* place in the client that references the `AbilityUI` path; `Input/init.lua` never reaches into `PlayerGui`.

## 8. Failure Modes & Edge Cases

| Case | Behavior |
|---|---|
| `EquippedPower` never set (loadout missing) | `powerEntry` stays `nil`, `refresh()` hides UI, no keybinds bound. No error. |
| `EquippedPower` set to an unknown name | `SharedPowerConfigs.POWERS_BY_NAME[name]` returns nil → treated same as "no power equipped" (hidden) + `warn(`[POWER] Unknown EquippedPower: {name}`)`. |
| Round ends mid-cooldown | `refresh()` hides UI; `cancelCooldown` runs. Server would reject the next press with `InvalidState` anyway. |
| Player dies mid-cooldown | Same as above, triggered by `Humanoid.Died`. |
| Server responds `success=false, reason=OnCooldown` | `pendingResponse = false`, no local cooldown started, button ungreys. Should only happen if client/server clocks drifted — the UX is a silent retry. |
| Server responds `success=false, reason=InvalidTarget` | Same — ungrey. Can't really happen since payload is always `{}`, but the code path is uniform. |
| Player spams `F` faster than the debounce | First press goes through, subsequent presses all pass the `isActivatable()` check only after the previous response arrives. `pendingResponse` gates them out. |
| Power attribute changes mid-cooldown (e.g. future power-swap feature) | `cancelCooldown()` + `refresh()` — button re-displays with the new power's name, no leftover cooldown. |
| Stale response arrives after a newer press | `payload.sequenceId ~= state.sequenceId` → dropped. |
| Server response never arrives (remote dropped / server crash) | `pendingTimeout` fires after `cooldown + PENDING_TIMEOUT_BUFFER`, warns, clears `pendingResponse`, ungreys. No local cooldown started. Player can retry. |

No silent returns. Every early-return with a surprising cause emits a `warn`; the unknown-power case is the only one the module itself detects.

## 9. Testing

Per project policy: integration tests only. Two touch points:

### 9.1 Server attribute write — `src/Server/PowerService/integration_power_system.test.lua`

Extend the existing suite with:

| # | Case | Expected |
|---|---|---|
| N+1 | `PowerService.new` with resolved `.Power` | `player:GetAttribute("EquippedPower") == "<name>"` |
| N+2 | `PowerService.new` with missing `.Power` | attribute is `nil`, `.new` warned |
| N+3 | `:Destroy` | attribute is `nil` after destroy |

Reuses the existing fake-player fixture.

### 9.2 Client Input module

Client logic is not covered by our server-only integration harness. Manual verification against a live session:

1. Join a test server with a loadout → confirm `EquippedPower` attribute replicates, `AbilityUI` shows the power name, button is enabled.
2. Press `F` → power activates (verify via server log), button greys, countdown ticks down, restores at 0.
3. Press `F` during cooldown → no-op (button is disabled; keybind blocked by `isActivatable`).
4. Reach end of round → `AbilityUI` hides.
5. Die mid-cooldown → `AbilityUI` hides, cooldown canceled. Respawn in `RoundActive` → `AbilityUI` shows, ready state (no carried-over cooldown — cooldowns are local and fresh).
6. Touch device → on-screen button works identically.
7. Gamepad → `ButtonX` works.

No Studio-executable client tests — `ContextActionService` + `PlayerGui` behavior isn't faithfully simulable in the edit environment.

## 10. Constraints Honored

- **Server-authoritative.** Client sends a request; server decides. Cooldown display is local UX only.
- **No `Instance.new` for UI.** The existing `AbilityUI.Frame.Button` is toggled via `Enabled` / `Text` / `AutoButtonColor` / `TextTransparency`. Nothing is constructed.
- **UI passed as parameter.** `Input.init(abilityUi, button)` receives both; the module itself never touches `PlayerGui`.
- **No silent returns.** Every early-return is either on a guarded gate (`isActivatable`, `sequenceId` mismatch) or carries a `warn`.
- **One file, one responsibility.** Input binding stays in `InputRouter`; UI + cooldown state stays in `Input/init.lua`; server attribute write stays in `PowerService`. No cross-cutting.
- **Configuration in one place.** Display names + cooldowns in `src/Shared/Power/Configs.lua` (client + server). Keybinds in `InputRouter/Configs.lua`. Client display tuning (update interval) in `PowerController/Input/Configs.lua`.
- **Depend on contracts, not implementations.** Client reads the `EquippedPower` attribute; it doesn't call into `PowerService` or reach into `TeleportMetadataService`. Swap the attribute source and nothing downstream changes.
- **`--//` comments only where design choice is non-obvious.**

## 11. Open / Deferred

- **Power icons.** Drop-in swap later: add `iconId` to `Configs.POWERS[X]`, change `Button.Text = displayName` to set an `ImageLabel` child's `Image` when `iconId` exists, fall back to text otherwise.
- **Rebinding UI.** Keybind lives in `InputRouter/Configs.lua` today; a future settings panel would read/write there.
- **Radial cooldown sweep.** The current countdown is `TextTransparency` dim + "N.Ns" text. A radial overlay is a visual polish item, not a design shift.
- **Separate effect + input controllers.** Currently folded into one `PowerController/` folder with `Effects/` + `Input/` subdirs. If either grows significantly, splitting is straightforward.
- **Activation SFX / hit-confirm.** No sound on activation today. Follow-up could hook into `ClientEventBus` with a `PowerActivated` fire from `onServerResponse` on success.
