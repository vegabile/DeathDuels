# DeathDuels Configuration Reference

Last updated: 2026-05-18

## Runtime Modes

`src/Shared/GlobalConfigs.lua` derives `TEST_MODE` from `RunService:IsStudio()`.

- In Studio, the round service can use local template teleport data and teleport-out calls are skipped.
- In live servers, production teleport metadata, reconnect tickets, and return teleports are used.
- Do not hardcode `TEST_MODE = true` for a release build.

## Match Teleport Data

Production joins must provide valid teleport data:

- `teamOnePlayers` and `teamTwoPlayers`: non-empty arrays of `{ UserId: positive integer, Name: string }`
- `queueType`: valid index into `Round.Configs.GAME_MODES`
- `mapName`: registered map model name
- `timestamp`: number
- `matchId`: non-empty string
- `placeId`: positive number
- `reservedServerAccessCode`: non-empty string
- `loadouts`: optional map keyed by user id string; invalid or missing entries default to `Round.Configs.DEFAULT_LOADOUT`

Late joiners are accepted only when their teleport data matches the active `matchId` and their `UserId` belongs to the original roster. Reconnect joins must use reconnect teleport data and a valid active reconnect ticket.

## Maps

Register playable maps in `src/Shared/Map/Configs.lua`:

```lua
REGISTERED_MAPS = {
    "Skate Park",
    "TestMap",
}
```

Each registered map must be a `Model` under `ReplicatedStorage.Maps`.

Spawn anchors are `BasePart` descendants named:

- `RedSpawn`
- `BlueSpawn`

`MapValidator.validate(mapName, queueType)` requires enough red and blue spawn parts for the selected game mode's `playersPerTeam`. If no queue type is supplied, it falls back to `MAX_PLAYERS_PER_TEAM`.

Teams alternate spawn colors each round: odd rounds give team 1 red spawns, even rounds give team 1 blue spawns.

## Loadouts And Persistence

Runtime match loadouts come from teleport metadata.

`DataService` currently stores persistent ownership sets only:

- `Knives`
- `Guns`
- `Coin`

Equipped weapon selection is not currently persisted by `DataService`. Do not call old equipped-knife APIs such as `EquipKnife` or `GetEquippedKnifeName`; they are not implemented.

## Weapons

Knife templates live under `ReplicatedStorage.KnifeModels`.

- Each child must be a `Tool`.
- `Handle` must be a `BasePart`.
- Optional `Hitbox` must be a `BasePart`; if missing, `WeaponDistributor` creates one.

Gun templates live under `ReplicatedStorage.GunModels`.

- Each child must be a `Tool`.
- `Handle` must be a `BasePart`.
- `ShootPoint` must be an `Attachment`; if absent, a valid `ShootAttachment` is renamed, otherwise a default attachment is created.

Reload/ammo gameplay is intentionally disabled in the stabilization build. The active gun action set is `Shoot` only.

## Powers

Runtime powers are registered from `ServerScriptService.PowerService.Powers` and exposed through `Shared/Power/Configs.lua`.

Timed power effects are round-scoped and tokenized so round transitions and overlapping effects clean up safely. Blinding is intentionally removed from the active power list until it can be rebuilt as an authoritative raycast projectile.

## Focused Studio Tests

Tests are plain ModuleScripts with assertions. The preferred local runner is Lune:

```sh
lune run scripts/run-lune-tests.luau
```

You can also run the same modules in Studio edit mode with `require(...)`; do not start a playtest just to run module tests.

```lua
require(game.ReplicatedStorage.Gun["PayloadValidator.test"])
require(game.ReplicatedStorage.Knife["PayloadValidator.test"])
require(game.ReplicatedStorage.Spectate["derive.test"])
require(game.ServerScriptService.RoundService["PlayerState.test"])
require(game.ServerScriptService.RoundService["TeleportUtility.test"])
require(game.ServerScriptService.ServerEventBus["ServerEventBus.test"])
```

Expected result: each module prints `passed` and returns `true`.

## Build

Use:

```sh
argon build -o .bg-shell/stabilization-build.rbxlx -x -y
```

The previous stale `ServerPackages` project mapping has been removed; `default.project.json` now maps only existing source paths.
