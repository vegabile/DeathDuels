# Spectate System Design

Date: 2026-04-16
Status: Proposed

## Overview

Client-only spectate, derived entirely from the existing `RoundUpdate` snapshot stream. Zero new server code, zero new remotes. `SpectateController` subscribes to `ClientEventBus`, recomputes its state on each snapshot via a pure derivation function, and owns target selection + camera.

## Hard Constraints

- Server only sends data/events. It never manages client spectate session state.
- Client stores data and derives everything: `canSpectate`, `isSpectating`, `availableTargets`, `currentTargetUserId`, camera behavior.

## Server Responsibilities

None new. `RoundSystem:_broadcastUpdate` already fires `RoundUpdate` (a full snapshot) on: round start, round end, player death, player disconnect, state transitions, and player registration. That is the entire data contract.

## Client Responsibilities

- Subscribe to `ClientEventBus:Connect("RoundUpdate")`.
- Recompute `SpectateClientState` on every snapshot via `derive.lua` (pure).
- Resolve target: keep prev if still valid; otherwise first available; otherwise `nil`.
- If `availableTargets` is empty, end spectate (clear target, `isSpectating = false`, restore default camera). Do nothing else — the round lifecycle will end the match and teleport naturally.
- Restore default camera whenever `canSpectate` flips false or `currentTargetUserId` becomes `nil`.
- Camera: when `isSpectating`, set `Workspace.CurrentCamera.CameraSubject` to the target's `Humanoid`; otherwise set it to the local player's `Humanoid` if present, otherwise leave as-is.
- Expose `SelectTarget(userId)`, `SelectNext()`, `SelectPrevious()`, `Clear()` for UI to call.

## Rules / Derivation

Inputs: `snapshot`, `localUserId`, `prevTargetUserId`.

```
isRoundActive   = snapshot.state == "RoundActive"

per player entry in snapshot.playerStates:
  userId        = entry.player.UserId
  isInGame      = entry.isInGame
  isEliminated  = entry.status == "Dead"

selfInGame      = players[localUserId].isInGame       -- false if absent
selfEliminated  = players[localUserId].isEliminated   -- false if absent

canSpectate     = isRoundActive and (selfEliminated or not selfInGame)

availableTargets = sorted asc userIds where
                   isInGame and not isEliminated and userId ~= localUserId

currentTargetUserId =
    prevTargetUserId if prevTargetUserId is in availableTargets
    else availableTargets[1]
    else nil

isSpectating    = canSpectate and currentTargetUserId ~= nil
```

When `canSpectate` is false, `currentTargetUserId` is forced to `nil` regardless of prior value.

## Client State Shape

```lua
export type SpectateClientState = {
    isRoundActive: boolean,
    selfInGame: boolean,
    selfEliminated: boolean,
    players: { [number]: { isInGame: boolean, isEliminated: boolean } },
    canSpectate: boolean,
    availableTargets: { number },
    currentTargetUserId: number?,
    isSpectating: boolean,
}
```

## Server Data Shape (Reused)

No new events. Client reads these fields from the existing `RoundUpdate` snapshot:

```
snapshot.state: GameState                       -- "RoundActive" gates spectate
snapshot.playerStates: {
    {
        player: Player,
        status: "Alive" | "Dead" | "Disconnected" | "Skipped",
        isInGame: boolean,
        ...                                      -- other fields ignored
    }
}
```

## File Layout

Follows the project service pattern (`init.lua` + `executor.*.lua` + `Types.lua` + `Configs.lua`):

- `src/Client/SpectateController/init.lua` — public API, stores state, applies derivation results, owns camera side effects, exposes `SelectTarget` / `SelectNext` / `SelectPrevious` / `Clear` / `GetState`. Camera and any UI references are injected through the constructor/`Init` rather than looked up globally, so tests can pass `nil`.
- `src/Client/SpectateController/executor.client.lua` — resolves `Workspace.CurrentCamera`, wires `ClientEventBus:Connect("RoundUpdate")`, and any input bindings for next/prev target.
- `src/Client/SpectateController/derive.lua` — pure `(snapshot, localUserId, prevTargetUserId) -> SpectateClientState`. No callbacks, no signals, no Roblox API calls.
- `src/Client/SpectateController/Types.lua` — exports `SpectateClientState`.
- `src/Client/SpectateController/Configs.lua` — input keys and any camera tunables.

## Testing

Integration tests target `derive.lua`:

- Round not active → `canSpectate = false`, `currentTargetUserId = nil`.
- Round active, self alive + in game → `canSpectate = false`.
- Round active, self dead → `canSpectate = true`, `availableTargets` excludes self and excludes `Dead`/`Disconnected`/`Skipped`/`not-in-game`.
- Round active, self not in game (`Skipped`) → `canSpectate = true`.
- Prev target still valid → retained.
- Prev target invalidated → falls to first available.
- All targets gone → `currentTargetUserId = nil`, `isSpectating = false`.
- Snapshot with no entry for local user → `selfInGame = false`, `selfEliminated = false` (hence `canSpectate = true` while round active).

UI and `Workspace.CurrentCamera` are passed in as parameters; tests pass `nil` where the project's convention allows.
