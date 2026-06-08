# Round map-loading & "ready" contract

This documents a non-obvious cross-module contract between the server `RoundService`
and the client `RoundController` that was previously captured in inline code comments.
It assumes `StreamingEnabled` is **ON**.

## Why it exists

When a round starts the server positions players at their combat spawns, then unfreezes
them into `RoundActive`. With streaming on, a client does not hold the whole map — so it
must confirm the area around its own spawn has actually streamed in (and its assets are
preloaded) before the server releases it, otherwise a player can be unfrozen into a
half-loaded map.

## The signal flow

1. **Server positions + anchors (`PreparingPlayers`).**
   `RoundOrchestrator.exitSkippedOrPosition` pivots the character to its combat spawn and
   sets `hrp.Anchored = true`. The anchored root is the deterministic *"I'm at my spawn"*
   signal for the client — no spawn coordinates are sent over the network.

2. **Client streams + preloads (`MapLoader.ensureReady`).**
   `RoundController` calls `MapLoader.ensureReady(mapName)` on every `PreparingPlayers`
   snapshot; it is idempotent and acts only once per client. It waits for the local
   character's root to become anchored, then:
   - calls `Player:RequestStreamAroundAsync(root.Position, ...)` to stream the spawn region
     and yield until those parts are present. **Note:** `RequestStreamAroundAsync` lives on
     `Player`, *not* `Workspace`.
   - `ContentProvider:PreloadAsync` on the streamed-in map model (textures/meshes/sounds).
   - fires `Configs.MAP_READY_REMOTE` (`"RoundMapReady"`).
   A hard cap (`Configs.MAP_LOAD_TIMEOUT`, 15s) reports ready best-effort on an independent
   thread even if streaming or preload stalls, so a slow client is never wrongly `Skipped`.

3. **Server banks the readiness fact (`RoundSystem:_onClientMapReady`).**
   The server records the `MapReady` readiness fact only while in `PreparingPlayers` — the
   window in which the client has actually been positioned and anchored. This rejects an
   early or spoofed fire (e.g. during `AssigningTeams`) before the spawn region has streamed
   in. `RoundActive` is gated on every required client having banked `MapReady`.

## Gating is first-round-only

`MapReady` is reported once per client; the server records the fact and never clears it,
matching `READINESS_GRACE_FIRST_ROUND`. Subsequent rounds do not re-gate on streaming.

## Key references

- `src/Server/RoundService/RoundOrchestrator.lua` — `exitSkippedOrPosition` (position + anchor),
  `enterPreparingPlayers` (readiness gate), `enterRoundActive` (release).
- `src/Client/RoundController/MapLoader.lua` — `ensureReady`, `waitForAnchoredRoot`.
- `src/Client/RoundController/init.lua` — invokes `MapLoader.ensureReady` on `PreparingPlayers`.
- `src/Server/RoundService/init.lua` — `_onClientMapReady` banks the fact.
- `src/Shared/Round/Configs.lua` — `MAP_READY_REMOTE`, `MAP_LOAD_TIMEOUT`,
  `READINESS_GRACE_FIRST_ROUND`, `REQUIRED_FACTS`.
