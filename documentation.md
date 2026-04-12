# DeathDuels Configuration Reference

Two things **must** be configured before the game works end-to-end:

1. Set `LOBBY_PLACE_ID` in `src/Shared/Round/Configs.lua`
2. Register your maps in `src/Shared/Map/Configs.lua`

Everything else has safe defaults.

---

## Setting the Lobby Place ID

Open `src/Shared/Round/Configs.lua` and replace `0` with your lobby's Roblox Place ID:

```lua
LOBBY_PLACE_ID = 0,  -- ← change this
```

This is the place all players teleport to when a game ends (or aborts). If left as `0`, the game will warn and skip the teleport rather than looping on a broken call.

---

## Registering Maps

Open `src/Shared/Map/Configs.lua` and add each map name to `REGISTERED_MAPS`:

```lua
REGISTERED_MAPS = {
    "Arena",
    "Desert",
},
```

Rules:
- Each name must **exactly** match the `Model` name inside `ReplicatedStorage.Maps`
- The asset must be a **Model** instance (not a Folder or other class)
- The model must contain at least `MAX_PLAYERS_PER_TEAM` parts named `"RedPart"` and `"RedPart"` count of `"BluePart"` (see Map Spec below)

Maps not in this list are rejected at join-time by `MapValidator` — they will never load.

---

## Map Spec

Every map model must satisfy all of the following or validation will fail:

| Requirement | Detail |
|-------------|--------|
| Is a `Model` | The root asset in `ReplicatedStorage.Maps` must be a Model, not a Folder |
| `RedPart` descendants | At least `MAX_PLAYERS_PER_TEAM` (default: `2`) parts named `"RedPart"` anywhere in the model |
| `BluePart` descendants | At least `MAX_PLAYERS_PER_TEAM` (default: `2`) parts named `"BluePart"` anywhere in the model |
| Name in registry | The model's name must appear in `REGISTERED_MAPS` in `src/Shared/Map/Configs.lua` |

Spawn parts (`RedPart` / `BluePart`) are the CFrame anchors used to position players at round start. Players are placed at the part's CFrame + `Vector3(0, 3, 0)`. Parts can be anywhere inside the model — depth in the hierarchy doesn't matter.

Teams alternate spawn colors each round: odd rounds → team 1 gets Red, even rounds → team 1 gets Blue.

---

## All Configurable Constants

### `src/Shared/Round/Configs.lua`

| Constant | Default | Description |
|----------|---------|-------------|
| `LOBBY_PLACE_ID` | `0` | Place ID to teleport players to after game over. **Must be set.** |
| `WAITING_PERIOD` | `10` | Seconds to wait for all players to join before forcing AssigningTeams |
| `ROUND_DURATION` | `60` | Max seconds per round before time-expiry winner is decided |
| `ROUND_INTERMISSION_DURATION` | `5` | Seconds between rounds (stats locked, no kills counted) |
| `GAME_OVER_DURATION` | `8` | Seconds to display game-over screen before teleporting out |
| `RESPAWN_DELAY` | `3` | Unused by the round system directly; reserved for future use |
| `CHARACTER_LOAD_TIMEOUT` | `10` | Seconds to wait for a character's `HumanoidRootPart` before warning and skipping |
| `RETRY_COUNT` | `3` | Number of teleport attempts before giving up |
| `EXPONENTIAL_BACKOFF_BASE` | `1` | First retry delay in seconds |
| `EXPONENTIAL_BACKOFF_EXPONENT` | `2` | Backoff multiplier per attempt (delays: 1s, 2s, 4s) |
| `ROUNDS_TO_WIN` | `5` | Rounds a team must win to end the match early |
| `MAX_ROUNDS` | `9` | Hard cap on total rounds; tiebreaker by win count |
| `MAX_PLAYERS_PER_TEAM` | `2` | Players per team; also the minimum spawn part count required per map |
| `SPAWN_PARTS.Red` | `"RedPart"` | Exact name of red-team spawn parts in map models |
| `SPAWN_PARTS.Blue` | `"BluePart"` | Exact name of blue-team spawn parts in map models |

### `src/Shared/Map/Configs.lua`

| Constant | Default | Description |
|----------|---------|-------------|
| `REGISTERED_MAPS` | `{}` | List of approved map names. **Must be populated.** |

---

## Running Tests

Tests run in the Studio edit environment via `mcp__robloxstudio__execute_luau`. Never start a playtest to run them.

**MapValidator tests** — validates registry, class checks, and spawn part counts:
```
require(game.ReplicatedStorage.Map["MapValidator.test"])
```
Or execute `src/Shared/Map/MapValidator.test.lua` directly via the MCP tool.

**RoundSystem tests** — validates state machine, PlayerState, TeamState, WinConditionEvaluator:
```
require(game.ServerScriptService.RoundService["RoundSystem.test"])
```

Expected output: `N passed, 0 failed`. Any `SKIP:` lines mean a prerequisite (e.g. `REGISTERED_MAPS` is empty) was not met — fill in the config and re-run.

---

## Adding a New Map: Checklist

1. Build the map model in Studio
2. Name the model exactly what you want (e.g. `"Arena"`)
3. Place at least 2 parts named `RedPart` and 2 named `BluePart` inside it
4. Move the model into `ReplicatedStorage.Maps`
5. Add the name to `REGISTERED_MAPS` in `src/Shared/Map/Configs.lua`
6. Run `MapValidator.test.lua` to confirm it passes

---

## Knife Model Selection

Players can own multiple knife models and equip one at a time. At round start, the equipped knife is distributed to the player.

### How Knife Models Are Stored

Each knife variant is a `Tool` instance inside `ReplicatedStorage.KnifeModels`. The Tool must have a `Handle` BasePart child. A `Hitbox` Part is auto-created if missing.

### How Equipped Knife Is Tracked

`DataService` stores a `Knives` array per player. Each entry has `{ id, name, equipped }`. Only one knife can have `equipped = true` at a time.

### API

```lua
DataService.AddKnife(player, knifeName)          -- adds knife to collection
DataService.EquipKnife(player, knifeId)           -- equips knife by id, unequips all others
DataService.GetEquippedKnifeName(player) -> string? -- returns equipped knife's name, or nil
```

### Resolution at Round Start

`WeaponDistributor` queries `DataService.GetEquippedKnifeName(player)` and looks up the matching template by name in `ReplicatedStorage.KnifeModels`. If no knife is equipped or the name doesn't match any template, the first template in the folder is used as default.

### Adding a New Knife Model: Checklist

1. Create a `Tool` instance in Studio with a `Handle` BasePart child
2. Name the Tool (e.g. `"Dagger"`) — this name is used for lookup
3. Place it inside `ReplicatedStorage.KnifeModels`
4. Give the knife to a player via `DataService.AddKnife(player, "Dagger")`
5. Equip it via `DataService.EquipKnife(player, knifeId)`
