# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Dev Commands

```bash
argon serve       # Start Argon sync server (keep running while editing in Studio)
argon build       # Build the place file to disk
wally install     # Install Lua dependencies into ServerPackages/
```

Execution for testing/debugging happens via `mcp__robloxstudio__execute_luau` in the edit environment — never start a playtest.

Never chain Bash commands with `&&` or `;` when each is individually allowed. Use separate parallel Bash tool calls instead.

## Project Mapping (Rojo/Argon)

```
src/Server   → ServerScriptService
src/Client   → StarterPlayer/StarterPlayerScripts
src/Shared   → ReplicatedStorage
```

## Architecture

### Service Pattern

Every service follows the same shape:

- `init.lua` — public API and state, no Roblox event wiring
- `executor.*.lua` — wires `PlayerAdded`, `PlayerRemoving`, and other Roblox events; calls into `init.lua`
- `Types.lua` — exported type definitions for that service
- `Configs.lua` — all magic values and constants; nothing is scattered

This keeps logic testable and decoupled from the Roblox lifecycle.

### Weapon System (Knife / Gun)

Client-authoritative prediction with server correction:

1. Client (`KnifeController` / `GunController`) applies the action locally via its state machine and fires `KnifeAction_{UserId}` / `GunAction_{UserId}` with a `sequenceId`.
2. Server (`KnifeService` / `GunService`) validates the payload (`PayloadValidator`), checks rate limits and state, then executes the action.
3. Server sends back either `CooldownReset` (accepted) or `StateOverride` (rejected — rolls back client state). Stale overrides are discarded by comparing `sequenceId`.

Each weapon has a mirrored `Shared/` module containing its state machine, payload validator, utility functions, types, and configs. Server and client both share these.

### ActionRegistry

`ActionRegistryFactory` (`src/Shared/ActionRegistryFactory.lua`) produces a registry from an action list. Each action has a `name`, `cooldown`, `clientExecute`, and `serverExecute`. Server and client each have their own `ActionRegistry.lua` that builds from their respective action modules.

### NetworkRouter

Singleton (`src/Shared/NetworkRouter`) that wraps RemoteEvents/RemoteFunctions. Server creates remotes; both sides call `NetworkRouter:Get(name)` to retrieve them. Per-player remotes are named `KnifeAction_{UserId}` and `GunAction_{UserId}` and are created/destroyed on `PlayerAdded`/`PlayerRemoving`.

### RoundService

Drives the match lifecycle on private servers. Reads teleport metadata from `player:GetJoinData().TeleportData` on `PlayerAdded`, validates it at the boundary (`TeleportDataValidator`), then populates `TeleportMetadataService` (a singleton). State transitions are enforced by `RoundStateMachine` against `LEGAL_TRANSITIONS` in `Shared/Round/Configs`. Supporting modules are pure data containers:

- `PlayerState` — per-player status, stats, lock/unlock
- `TeamState` — computes alive/dead/disconnected counts via `Recalculate()`
- `WinConditionEvaluator` — stateless functions; takes snapshots, returns `(isOver, winningTeam?)`
- `TeleportUtility` — returns players to lobby with exponential-backoff retry

### DataService

Wraps ProfileService (Wally dep). Player data schema: `{ Coin, Knives, Guns }`. All mutations go through DataService methods — never write to `profile.Data` directly elsewhere.

### EventBus

`ClientEventBus` and `ServerEventBus` are simple signal buses for intra-client and intra-server decoupling respectively. They do not cross the client/server boundary.
