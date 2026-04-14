# Mobile Weapon Input — Design Spec

**Date:** 2026-04-13
**Status:** Draft (awaiting user review)
**Branch:** readiness-ownership (intended follow-up branch TBD)

## Problem

The current weapon input layer is desktop-only in practice:

1. `src/Client/InputPosition.lua` uses `player:GetMouse()` to derive aim target. On mobile, `GetMouse()` returns a screen position tied to the character, not an aim point — so knife throws and gun shots fire into the ground on touch devices.
2. `src/Client/InputRouter/Configs.lua` wires `touchButton = true` for Stab, Throw, and Shoot, which auto-generates CAS buttons for mobile. The buttons exist, but pressing them invokes the broken mouse-based aim path above. They also expose no tap-vs-hold discrimination.
3. There is no `Reload` action anywhere in the codebase — not in `src/Shared/Gun/Configs.lua`, `GunStateMachine`, either `ActionRegistry`, or the server. A mobile-friendly reload does not yet exist to be made mobile-friendly.

## Goals

- Gun: tap-in-world to shoot (LMB on PC, screen tap on mobile) with a pan-vs-tap discriminator on touch
- Gun: add a cosmetic `Reload` action — `R` key on PC, CAS touch button on mobile
- Knife: tap-in-world for Stab (short press <0.4s), hold-in-world for Throw (press ≥0.4s, release), unified across PC and mobile
- Remove Q/E knife key bindings; unify PC and mobile around a single pointer-gesture model
- Mobile aim uses camera `LookVector`; PC aim keeps existing mouse raycast
- Zero server-side changes to knife logic; server gun gains only the new cosmetic `Reload` action

## Non-goals

- Real ammo system. `Reload` is cosmetic: a brief cooldown blocks `Shoot`, plays animation + sound, no magazine count, no "out of ammo" state.
- Gamepad support. `InputRouter`'s current `ButtonL1`/`ButtonR1`/`ButtonR2` gamepad bindings are removed along with `InputRouter` itself; re-introducing gamepad is a separate follow-up spec.
- Real mobile hardware testing. Studio device emulator is the verification surface for this spec.
- Tap-in-world without a button for Reload. Reload is deliberately a discrete action (key or CAS button), not a gesture.

## Decisions (locked during brainstorming)

| # | Decision | Choice |
|---|---|---|
| 1 | Mobile aim source | Camera `LookVector`; PC keeps mouse raycast |
| 2 | Gun shoot input | LMB on PC, tap-in-world on mobile (no CAS button); pan-vs-tap discriminator on touch |
| 3 | Reload scope | Cosmetic only — no ammo system |
| 4 | Knife gesture | Short release (<0.4s) → Stab; long release (≥0.4s) → Throw |
| 4b | Hold threshold | `0.4s` |
| 5 | PC knife binding | LMB on PC (Q/E removed) |
| 6 | Reload PC binding | `R` key on PC; CAS touch button on mobile; no PC button |
| — | Device detection | Shared `src/Shared/DeviceType.lua` (user provides implementation) with API `DeviceType.getDevice(): string` returning `"PC"` or `"Mobile"` |
| — | Architecture | Platform-split input modules (`PCInputModule`, `MobileInputModule`) selected at startup by device detection, exposing a shared `WeaponInputModule` interface |
| — | `InputRouter/` fate | Deleted entirely — no non-weapon consumers exist |

## Architecture

```
src/Client/
├── WeaponInput/                NEW — platform-split input umbrella
│   ├── init.lua                requires DeviceType; returns PCInputModule OR MobileInputModule
│   ├── Types.lua               WeaponInputModule interface, GestureState, handler types
│   ├── Configs.lua             HoldThreshold=0.4, PanDragThreshold=25, ReloadKeyCode, ReloadTouchButtonName
│   ├── GestureRecognizer.lua   pure data module: down/move/up → Tap|HoldRelease|Pan|Ignored
│   ├── PCInputModule.lua       LMB gesture, R-key reload, mouse-raycast aim
│   ├── MobileInputModule.lua   Touch gesture, CAS reload button, camera-lookvector aim
│   └── executor.client.lua     require-only
│
├── InputPosition.lua           DELETED
├── InputRouter/                DELETED (all files)
│
├── KnifeController/
│   ├── init.lua                MODIFIED: performAction gains (actionName, aimTarget?)
│   └── executor.client.lua     MODIFIED: subscribe via WeaponInput.bindKnife
│
└── GunController/
    ├── init.lua                MODIFIED: performAction gains (actionName, aimTarget?)
    ├── Actions/
    │   ├── ShootAction.lua     unchanged
    │   └── ReloadAction.lua    NEW — cosmetic client execute
    ├── ActionRegistry.lua      MODIFIED: register Reload
    └── executor.client.lua     MODIFIED: subscribe via WeaponInput.bindGun

src/Server/GunService/
├── Actions/
│   └── ReloadAction.lua        NEW — cosmetic server execute
└── ActionRegistry.lua          MODIFIED: register Reload

src/Server/KnifeService/        unchanged (gesture model is client-only)

src/Shared/
├── DeviceType.lua              NEW (user provides implementation)
└── Gun/
    ├── Configs.lua             MODIFIED: add Reload to ValidActions + Reload* fields
    ├── GunStateMachine.lua     MODIFIED: add isReloading; Reload branch in setActionActive/resetAction
    └── PayloadValidator.lua    MODIFIED: accept Reload action (no directionVector required)
```

## Module specifications

### `src/Shared/DeviceType.lua` (new, user implements)

```lua
local DeviceType = {}

function DeviceType.getDevice(): string  --// returns "PC" or "Mobile"
    --// user-provided implementation
end

return DeviceType
```

### `WeaponInput/init.lua`

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DeviceType = require(ReplicatedStorage.DeviceType)

if DeviceType.getDevice() == "Mobile" then
    return require(script.MobileInputModule)
end
return require(script.PCInputModule)
```

Single one-shot selection at startup. The returned module is a static table implementing the `WeaponInputModule` interface.

### `WeaponInput/Types.lua`

```lua
export type KnifeHandlers = {
    onStab: () -> (),
    onThrow: (aimTarget: Vector3) -> (),
}

export type GunHandlers = {
    onShoot: (aimTarget: Vector3) -> (),
    onReload: () -> (),
}

export type WeaponInputModule = {
    bindKnife: (handlers: KnifeHandlers) -> (),
    unbindKnife: () -> (),
    bindGun: (handlers: GunHandlers) -> (),
    unbindGun: () -> (),
}

export type GestureState = {
    isDown: boolean,
    startTime: number,
    startPosition: Vector2,
    currentPosition: Vector2,
    maxDragDistance: number,
}

export type GestureConfig = {
    HoldThreshold: number,
    PanDragThreshold: number,
}

export type GestureResult = "Tap" | "HoldRelease" | "Pan" | "Ignored"

return nil
```

### `WeaponInput/Configs.lua`

```lua
return {
    HoldThreshold = 0.4,            --// seconds; release under this = Tap, at or over = HoldRelease
    PanDragThreshold = 25,          --// pixels; exceeded drag discards the gesture as a camera pan
    ReloadKeyCode = Enum.KeyCode.R, --// PC reload binding
    ReloadTouchButtonName = "GunReload",
}
```

### `WeaponInput/GestureRecognizer.lua`

Pure data module. No Roblox services, no signals, no state outside the struct passed in.

```lua
local GestureRecognizer = {}

function GestureRecognizer.new(): Types.GestureState
    return {
        isDown = false,
        startTime = 0,
        startPosition = Vector2.zero,
        currentPosition = Vector2.zero,
        maxDragDistance = 0,
    }
end

function GestureRecognizer.onDown(state, position: Vector2)
    state.isDown = true
    state.startTime = os.clock()
    state.startPosition = position
    state.currentPosition = position
    state.maxDragDistance = 0
end

function GestureRecognizer.onMove(state, position: Vector2)
    if not state.isDown then return end
    state.currentPosition = position
    local drag = (position - state.startPosition).Magnitude
    if drag > state.maxDragDistance then
        state.maxDragDistance = drag
    end
end

function GestureRecognizer.onUp(state, config): Types.GestureResult
    if not state.isDown then return "Ignored" end
    if state.maxDragDistance > config.PanDragThreshold then return "Pan" end
    local duration = os.clock() - state.startTime
    if duration < config.HoldThreshold then return "Tap" end
    return "HoldRelease"
end

function GestureRecognizer.reset(state)
    state.isDown = false
    state.maxDragDistance = 0
end

return GestureRecognizer
```

Pan classification wins over hold: a drag is never a weapon action, regardless of duration.

### `WeaponInput/PCInputModule.lua`

Private state:

```lua
local knifeHandlers: Types.KnifeHandlers? = nil
local gunHandlers: Types.GunHandlers? = nil
local gesture = GestureRecognizer.new()
local inputBeganConn, inputChangedConn, inputEndedConn: RBXScriptConnection? = nil
local reloadKeyConn: RBXScriptConnection? = nil
```

`bindKnife(handlers)`:
1. Set `knifeHandlers = handlers`
2. `ensurePointerConnections()` — lazy connect on first bind

`bindGun(handlers)`:
1. Set `gunHandlers = handlers`
2. `ensurePointerConnections()`
3. `ensureReloadKeyConnection()` — connects `UserInputService.InputBegan` filtered to `Enum.KeyCode.R`, calls `handlers.onReload()`

`unbindKnife()` / `unbindGun()`:
1. Clear the respective handler
2. If both are `nil`, tear down pointer connections
3. `unbindGun` additionally disconnects the reload key listener

Pointer wiring:

```lua
local function ensurePointerConnections()
    if inputBeganConn then return end

    inputBeganConn = UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        GestureRecognizer.onDown(gesture, Vector2.new(input.Position.X, input.Position.Y))
    end)

    inputChangedConn = UIS.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if not gesture.isDown then return end
        GestureRecognizer.onMove(gesture, Vector2.new(input.Position.X, input.Position.Y))
    end)

    inputEndedConn = UIS.InputEnded:Connect(function(input, gameProcessed)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local result = GestureRecognizer.onUp(gesture, Configs)
        GestureRecognizer.reset(gesture)
        if result == "Ignored" or result == "Pan" then return end
        dispatchRelease(result)
    end)
end
```

Dispatch:

```lua
local function dispatchRelease(result: "Tap" | "HoldRelease")
    local aimTarget = getMouseAimTarget()
    if knifeHandlers then
        if result == "Tap" then
            knifeHandlers.onStab()
        elseif result == "HoldRelease" then
            knifeHandlers.onThrow(aimTarget)
        end
    elseif gunHandlers then
        if result == "Tap" then
            gunHandlers.onShoot(aimTarget)
        end
        --// HoldRelease on gun silently ignored — gun has no hold action
    end
end
```

`getMouseAimTarget(): Vector3` — the current `InputPosition.getInputPosition` body, moved verbatim. Returns a world target point; the weapon controller computes the unit direction against its own anchor (knife handle or gun shootPoint).

Test hooks exposed (for integration tests only, not called by production):

```lua
function PCInputModule._injectEvent(input, gameProcessed)
function PCInputModule._getConnectionCount(): number
```

### `WeaponInput/MobileInputModule.lua`

Same structural shape as `PCInputModule`. The only differences:

1. Input type filter is `Enum.UserInputType.Touch` instead of `MouseButton1`
2. `InputChanged` filters on `Touch` (not `MouseMovement`)
3. Drag-distance matters (it does not on PC because LMB never drags for camera)
4. Aim source is `getCameraAimTarget`, not `getMouseAimTarget`
5. Reload is wired via `ContextActionService:BindAction` with `createTouchButton = true`

`UIS.InputEnded` fires for every released touch regardless of `gameProcessed`, so touches that start in world and end on a CAS-consumed button still trigger gesture cleanup — no separate `TouchEnded` listener needed. If playtest uncovers an edge case where a gesture state leaks (e.g. engine-cancelled touches), a `UIS.TouchEnded` fallback can be added without changing the module shape.

`getCameraAimTarget`:

```lua
local function getCameraAimTarget(): Vector3
    local camera = workspace.CurrentCamera
    local origin = camera.CFrame.Position
    local direction = camera.CFrame.LookVector
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { Players.LocalPlayer.Character }
    local result = workspace:Raycast(origin, direction * 1000, params)
    if result then return result.Position end
    return origin + direction * 1000
end
```

Reload button wiring:

```lua
local function ensureReloadButton()
    if reloadButtonBound then return end
    ContextActionService:BindAction(
        Configs.ReloadTouchButtonName,
        function(_, inputState)
            if inputState ~= Enum.UserInputState.Begin then return end
            if gunHandlers and gunHandlers.onReload then
                gunHandlers.onReload()
            end
        end,
        true  --// createTouchButton
    )
    reloadButtonBound = true
end
```

`unbindGun` unbinds the action so the button is destroyed when the gun is unequipped.

The `gameProcessed` guard on `InputBegan` automatically excludes touches consumed by the mobile thumbstick, jump button, chat, and the Reload CAS button itself — so tapping the Reload button can never accidentally also emit a `Shoot`.

### `KnifeController.performAction` — signature change

Current: `function KnifeController.performAction(actionName: string)` — internally calls `InputPosition.getInputPosition()` to compute throw direction.

New: `function KnifeController.performAction(actionName: string, aimTarget: Vector3?)` — `InputPosition` require and internal call deleted. When `actionName == "Throw"`, the function uses the provided `aimTarget` to compute `(aimTarget - handle.Position).Unit`. The zero-length-delta abort guard, state machine call, network call, and safety timeout thread are unchanged.

Stab does not use `aimTarget` (nil).

### `GunController.performAction` — signature change

Same shape. Current `InputPosition.getInputPosition()` call deleted. `Shoot` branch uses `(aimTarget - shootPoint.WorldPosition).Unit`. `Reload` branch is new — hands off to `ActionRegistry.getAction("Reload")` like any other action, no `aimTarget`.

### Knife executor changes

```lua
--// src/Client/KnifeController/executor.client.lua
local WeaponInput = require(script.Parent.Parent.WeaponInput)

--// on knife equipped:
WeaponInput.bindKnife({
    onStab = function() KnifeController.performAction("Stab", nil) end,
    onThrow = function(aimTarget) KnifeController.performAction("Throw", aimTarget) end,
})

--// on knife unequipped / died:
WeaponInput.unbindKnife()
```

Existing `InputRouter.bindWeapon`/`unbindWeapon` calls are removed.

### Gun executor changes

```lua
--// src/Client/GunController/executor.client.lua
WeaponInput.bindGun({
    onShoot = function(aimTarget) GunController.performAction("Shoot", aimTarget) end,
    onReload = function() GunController.performAction("Reload", nil) end,
})
```

### Reload action — shared gun changes

`src/Shared/Gun/Configs.lua`:

```lua
ValidActions = { "Shoot", "Reload" },  --// was { "Shoot" }
ReloadCooldown = 2.0,
ReloadDuration = 2.0,
ReloadAnimationId = "",  --// empty until assigned
ReloadSoundId = "",
```

`src/Shared/Gun/GunStateMachine.lua`:

- Add `isReloading: boolean` to `new()` and `serialize()`
- `setActionActive` gains a `Reload` branch that sets `isReloading = true`. `Shoot` branch rejects when `isReloading == true`
- `resetAction("Reload")` clears `isReloading`
- `resetAll` clears both flags

`src/Shared/Gun/PayloadValidator.lua`: accept `"Reload"` as a valid `desiredAction`. `Reload` payloads must not include a `directionVector` (reject if present).

### Reload action — client and server

`src/Client/GunController/Actions/ReloadAction.lua` (new):

```lua
local SharedConfigs = require(game:GetService("ReplicatedStorage").Gun.Configs)

return {
    name = "Reload",
    cooldown = SharedConfigs.ReloadCooldown,
    clientExecute = function(stateMachine)
        --// play animation + sound if configured; otherwise no-op
        --// state machine locking is handled by performAction
    end,
}
```

`src/Server/GunService/Actions/ReloadAction.lua` (new): mirrors the client action. Validates, sets state machine flag, waits `ReloadDuration`, sends `CooldownReset` back. No ammo bookkeeping, no damage, no raycast.

Both action registries gain `Reload` alongside `Shoot`.

## Data flow

### Knife

```
User presses LMB (PC) or touches screen (Mobile)
  → active input module's GestureRecognizer tracks the stream
  → on release, classify:
      Pan (drag > 25px, mobile)       → discard
      duration < 0.4s                 → onStab()
      duration ≥ 0.4s                 → onThrow(aimTarget)
  → module computes aimTarget at release using platform rule:
      PC: mouse raycast hit point
      Mobile: camera lookvector raycast hit point (or synthesized far point)
  → KnifeController.performAction("Stab" | "Throw", aimTarget?)
  → (unchanged from here) state machine → NetworkRouter → server
```

### Gun shoot

```
User presses LMB (PC) or taps screen (Mobile)
  → classified as Tap → onShoot(aimTarget)
  → GunController.performAction("Shoot", aimTarget)
  → (unchanged) state machine → NetworkRouter → server
```

### Gun reload

```
PC:     UIS.InputBegan with KeyCode.R (gameProcessed = false)
Mobile: CAS "GunReload" button InputState.Begin
  → onReload()
  → GunController.performAction("Reload", nil)
  → state machine sets isReloading (blocks Shoot)
  → NetworkRouter → server validates Reload → CooldownReset after ReloadDuration
```

## Surface count

- **New:** 8 files — `WeaponInput/` (6) + `Client/Gun/Actions/ReloadAction.lua` + `Server/GunService/Actions/ReloadAction.lua`
- **Deleted:** 5 files — `InputPosition.lua`, `InputRouter/` (init, Configs, executor, and the folder itself)
- **Modified:** 9 files — `KnifeController/init.lua`, `KnifeController/executor.client.lua`, `GunController/init.lua`, `GunController/executor.client.lua`, `Client/GunController/ActionRegistry.lua`, `Server/GunService/ActionRegistry.lua`, `Shared/Gun/Configs.lua`, `Shared/Gun/GunStateMachine.lua`, `Shared/Gun/PayloadValidator.lua`
- **User-provided:** 1 file — `src/Shared/DeviceType.lua` (interface locked, body user-written)

Net +3 files.

## Testing strategy

Integration tests only. No unit tests.

### Studio integration tests via `mcp__robloxstudio__execute_luau`

Drive the full input stack by injecting synthetic `UserInputService` events at the module boundary (via `_injectEvent` test hooks) and assert observable state: state machines, network payloads captured through `NetworkRouter:Listen`, cooldown flags.

**Knife gesture cases (PCInputModule path):**

1. Equip knife → LMB down, up within 0.1s → assert `KnifeStateMachine.isStabbing == true`; assert captured payload has `desiredAction = "Stab"` with no `directionVector`
2. Equip knife → LMB down, wait 0.5s, up → assert `isThrowing == true`; payload has `desiredAction = "Throw"` and non-zero `directionVector`
3. Equip knife → LMB down, simulate cursor drag > `PanDragThreshold`, up → assert neither `isStabbing` nor `isThrowing` changed; no payload emitted
4. Equip knife → LMB down 0.5s, drag mid-hold, up → pan wins over hold; no throw emitted
5. Equip knife → LMB down exactly 0.399s → Tap; LMB down exactly 0.401s → HoldRelease (threshold boundary)

**Gun cases:**

6. Equip gun → tap → payload `Shoot` + direction vector present
7. Equip gun → press `R` → payload `Reload`; `GunStateMachine.isReloading == true`
8. Gun reloading, immediate tap → state machine rejects Shoot; no payload
9. Reload complete (server `CooldownReset` replayed), subsequent tap → Shoot fires normally

**Weapon swap cases:**

10. Equip knife → unequip → equip gun → tap → only gun handlers fire; knife state untouched
11. Equip knife → die → assert `WeaponInput.unbindKnife` was called and pointer connection count via `_getConnectionCount()` returns 0

**Mobile path:** same cases 1–11 driven against `MobileInputModule` using `UserInputType.Touch` events instead of `MouseButton1`.

### Server integration tests

Pattern follows the existing `test(round): integration test for readiness happy path` (commit `7d29da0`):

12. Test harness fires `GunAction_{UserId}` remote with `Reload` payload → server `PayloadValidator` accepts → server `ActionRegistry.getAction("Reload").serverExecute` runs → state machine flags `isReloading` → after `ReloadDuration`, `CooldownReset` response is received
13. Harness fires `Shoot` payload during active reload → server rejects via state machine → `StateOverride` response received

### Device-selector sanity sweep

14. Windows Studio, no touch enabled → `DeviceType.getDevice() == "PC"` → PC suite runs
15. Studio → Test → Device emulator → iPad → `DeviceType.getDevice() == "Mobile"` → Mobile suite runs

### Test hooks exposed by production modules

```lua
--// PCInputModule and MobileInputModule expose:
function Module._injectEvent(input, gameProcessed)  --// routes as if UIS fired it
function Module._getConnectionCount(): number       --// for teardown assertions
```

No UIS mocking — tests synthesize events at the production entry points. Production path is identical between test and runtime.

### Out of scope for tests

- Real mobile hardware (Studio emulator is sufficient)
- Gamepad (removed with InputRouter)
- Knife server-side changes (server knife is untouched)

## Open items

- `src/Shared/DeviceType.lua` body is user-provided; spec locks only the interface (`DeviceType.getDevice(): string` returning `"PC"` or `"Mobile"`)
- `ReloadAnimationId` and `ReloadSoundId` are empty strings in this spec — to be filled in when the user assigns asset IDs. Empty values fall through as no-op, per existing `SFXController.playAt` tolerance
- `ReloadCooldown` and `ReloadDuration` are placeholder values (`2.0`); tweak during playtest if the feel is off
