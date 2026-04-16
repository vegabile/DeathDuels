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
- If `availableTargets` is empty, end spectate (clear target, `isSpectating = false`, restore camera to self). Do nothing else — the round lifecycle will end the match and teleport naturally.
- Camera (always validate before touching): when `isSpectating`, look up the target `Player` via `Players:GetPlayerByUserId(currentTargetUserId)`, then check `target`, `target.Character`, and `target.Character:FindFirstChildOfClass("Humanoid")`. If any is missing, clear target, restore camera to self, `warn` the reason, and wait for the next snapshot to re-resolve. When not spectating, set `Workspace.CurrentCamera.CameraSubject` to the local player's `Humanoid` if it exists; otherwise set it to `nil`.
- Expose `SelectTarget(userId)`, `SelectNext()`, `SelectPrevious()`, `Clear()` for UI to call. `SelectTarget` rejects a userId not in `availableTargets` via `warn` and returns without changing state.

## Rules / Derivation

Inputs: `snapshot`, `localUserId`, `prevTargetUserId`.

**Step 1 — validate snapshot.** If any of the following fail, return the "spectate off" state (all booleans false, `players = {}`, `availableTargets = {}`, `currentTargetUserId = nil`) and `warn` with the reason:

- `snapshot` is a table
- `snapshot.state` is a string
- `snapshot.playerStates` is a table
- every entry in `snapshot.playerStates` has a `Player` in `player`, a string `status`, a boolean `isInGame`, and a number `team`

Malformed snapshots never enable spectate. Nothing is inferred from missing fields.

**Step 2 — derive.**

```
isRoundActive   = snapshot.state == "RoundActive"

per validated player entry:
  userId        = entry.player.UserId
  team          = entry.team
  isInGame      = entry.isInGame
  isEliminated  = entry.status == "Dead"

selfEntry       = players[localUserId]
if selfEntry == nil:
    -- fail closed: local user not in snapshot means we cannot decide
    canSpectate = false, availableTargets = {}, currentTargetUserId = nil

else:
    selfInGame      = selfEntry.isInGame
    selfEliminated  = selfEntry.isEliminated
    selfTeam        = selfEntry.team

    canSpectate     = isRoundActive and (selfEliminated or not selfInGame)

    availableTargets = userIds where
                       isInGame and not isEliminated and userId ~= localUserId,
                       ordered first by team-proximity (entries with
                       team == selfTeam come before the rest), then by
                       userId ascending within each group

    currentTargetUserId =
        prevTargetUserId if prevTargetUserId is in availableTargets
        else availableTargets[1]
        else nil

isSpectating    = canSpectate and currentTargetUserId ~= nil
```

When `canSpectate` is false, `currentTargetUserId` is forced to `nil` regardless of prior value.

`SelectNext` / `SelectPrevious` cycle through `availableTargets` in its current order: all teammates first, then all opponents, wrapping at the ends.

## Client State Shape

```lua
export type SpectateClientState = {
    isRoundActive: boolean,
    selfInGame: boolean,
    selfEliminated: boolean,
    players: { [number]: { team: number, isInGame: boolean, isEliminated: boolean } },
    canSpectate: boolean,
    availableTargets: { number },   -- teammates first (asc userId), then opponents (asc userId)
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
        team: number,
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

## Failure Handling (consolidated)

Every failure path restores camera to self (local `Humanoid` if present, else `nil`), clears `currentTargetUserId`, sets `isSpectating = false`, and emits a `warn`:

- Malformed snapshot (any shape-validation failure above).
- Local user missing from `snapshot.playerStates`.
- Target userId resolves to no `Player`, or `Player` has no `Character`, or `Character` has no `Humanoid`.
- `SelectTarget` called with a userId not in `availableTargets`.

Never silently return. Never fall back to "assume not in game".

## Testing

Integration tests target `derive.lua`:

- Round not active → `canSpectate = false`, `currentTargetUserId = nil`.
- Round active, self alive + in game → `canSpectate = false`.
- Round active, self dead → `canSpectate = true`, `availableTargets` excludes self and excludes `Dead`/`Disconnected`/`Skipped`/`not-in-game`.
- Round active, self not in game (`Skipped`) → `canSpectate = true`.
- Prev target still valid → retained.
- Prev target invalidated → falls to first available.
- All targets gone → `currentTargetUserId = nil`, `isSpectating = false`.
- Local user absent from `snapshot.playerStates` → spectate-off state (`canSpectate = false`).
- Malformed snapshots (non-table, missing `state`, missing `playerStates`, entry missing `team`/`status`/`isInGame`) → spectate-off state.
- Target ordering: given teammates on team 1 `{101, 103}` and opponents on team 2 `{102, 104}` with local on team 1, `availableTargets == {103, 102, 104}` (teammates asc, then opponents asc).

UI and `Workspace.CurrentCamera` are passed in as parameters; tests pass `nil` where the project's convention allows.
