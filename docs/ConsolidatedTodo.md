# DeathDuels Stabilization Status

Last updated: 2026-05-18

This file supersedes the earlier consolidated todo. The stabilization pass chose surgical fixes for broken match/combat behavior and deliberately removed unsafe unfinished surfaces instead of expanding scope.

## Completed In Stabilization Pass

- Round state is replayable for late server and client subscribers through sticky event-bus support.
- `RoundController` derives sticky client `RoundStateChanged` from `RoundUpdate` snapshots.
- Gun and knife clients gate actions on `RoundActive` before locking local state machines.
- Gun, knife, and power services initialize from replayed round state.
- Gun and knife malformed payload handling sanitizes sequence ids before raw payload indexing.
- Server weapon rejects now send corrective `StateOverride` responses when a player service state exists.
- Stab overlap and touched paths share shield-aware, distance-checked `TakeDamage` behavior.
- RoundActive round numbers are incremented before the first active broadcast.
- Positioning uses a round token plus `Positioning` status; timeout finalization skips any unpositioned player.
- Readiness no longer depends on `Model.PrimaryPart`; it uses `HumanoidRootPart` and `Humanoid`.
- Profile loaded readiness is queryable through `DataService:IsProfileLoaded` and replayed via sticky `ProfileLoaded`.
- Production teleport validation rejects malformed loadouts, duplicate user ids, non-positive user ids, invalid queue types, and invalid map spawn counts.
- Late normal joiners must match the active match id and original roster.
- Reconnect teleport data is validated and routed through `RoundSystem:RegisterReconnect`.
- Player snapshots serialize primitive player fields instead of live `Player` instances.
- Match rewards use cumulative match stats and include match-scoped action ids.
- Gun reload/ammo has been removed from the active action surface until a real ammo feature is designed.
- Blinding has been removed from active powers until an authoritative projectile implementation is designed.
- Timed powers use round-scoped/tokenized cleanup helpers.
- FakeClone now safely toggles `Archivable`, nil-checks clone creation, and fails gracefully.
- Power input waits briefly for slow Humanoid replication.
- Map, weapon-template, debug, SFX, docs, and project mapping cleanup have been updated.
- Focused assertion-based Studio test modules were added for payloads, spectate, event replay, player stats, and return rewards.

## Deliberately Deferred

- Real gun ammo, magazine, reserve, and reload semantics.
- Reintroducing Blinding as a raycast/LOS projectile.
- Persistent equipped weapon selection in `DataService`.
- Full replacement of the deleted historical test suite.
- Real production sound ids and missing knife idle/stab animation ids.

## Verification Targets

- `argon build -o .bg-shell/stabilization-build.rbxlx -x -y`
- `lune run scripts/run-lune-tests.luau` passed on 2026-05-18 after installing Lune 0.10.4 with Homebrew.
- Studio edit-mode module tests listed in `documentation.md`
- Manual Studio smoke: 1v1 full match, multi-round rewards, intermission weapon input, reconnect ticket flow, each remaining power once, malformed asset instance types, and join/leave during waiting/preparing/active states.
