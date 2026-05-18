# DeathDuels Consolidated Todo

Last audited: 2026-05-18

This is the consolidation list for the current dirty working tree. It merges the actionable findings from `docs/FoundBugs.md` with a fresh pass over `src`.

## Audit Rules

- Assume Studio-created assets and instances exist when code references them. Missing `Maps`, UI, model folders, `Remotes`, spawn parts, sounds, and animations are not todos by themselves.
- Track code that mishandles state, validates external instances incorrectly, leaves systems half implemented, or has stale docs/tests.
- The current working tree is the source of truth, including untracked power/reconnect files.

## P0 Broken/Blocking

- [ ] Fix weapon client locks outside `RoundActive`.
  - Current code: `GunController` and `KnifeController` listen for `ClientEventBus` event `RoundStateChanged`, but `RoundController` only fires `RoundUpdate`.
  - Impact: pressing weapon actions during intermission can lock the client state machine; server rejects inactive-round actions without sending a corrective `StateOverride`.
  - Fix direction: derive and fire client `RoundStateChanged` from round snapshots, add an explicit client-side round-active gate, and send state overrides on server inactive-state rejects.

- [ ] Make round state queryable/replayed for late service subscribers.
  - Current code: gun, knife, and power services cache current round state only from one-shot `ServerEventBus:Fire("RoundStateChanged")` events.
  - Impact: if a combat service loads after `RoundActive`, it can keep `currentRoundState == ""` and reject all actions.
  - Fix direction: keep current round state in a queryable authority or sticky event bus, and initialize each combat service from it when the service starts.

- [ ] Harden malformed weapon payload handling.
  - Current code: gun and knife services index `payload.sequenceId`; knife also logs `payload.desiredAction` before validation has proven `payload` is a table.
  - Impact: malformed/exploit remote payloads can error instead of cleanly rejecting.
  - Fix direction: add a safe sequence sanitizer like `Power.PayloadValidator`, never index raw payload before `type(payload) == "table"`, and always respond with a safe state override when possible.

- [ ] Fix stab damage paths so shield and distance rules are consistent.
  - Current code: heartbeat damage checks `ShieldActive`, but `.Touched` fallback goes through `processHitPlayer` and kills with `humanoid.Health = 0`.
  - Current code: heartbeat path references `attackerRoot` outside its scope, so the max stab distance guard is skipped there.
  - Impact: stabs can bypass shields and oversized/malformed hitboxes can damage past `MAX_STAB_DISTANCE`.
  - Fix direction: route both overlap and touched hits through one shield-aware function, use `TakeDamage`, and compute attacker/victim roots inside that shared function.

- [ ] Fix round positioning finalization.
  - Current code: outer positioning timeout treats `Alive` as terminal even if `positionedThisRound == false`; late positioning tasks can still mutate players after finalization.
  - Impact: players can remain counted alive while not actually positioned, or late tasks can skip/position players after the round has moved on.
  - Fix direction: introduce a pending-positioning state or equivalent guard, force-skip based on `positionedThisRound`, and require current round/state tokens before late tasks mutate state.

- [ ] Fix readiness completion for valid characters without `PrimaryPart`.
  - Current code: readiness records HRP/Humanoid facts, then `PlayerReadiness.isComplete` additionally requires `player.Character.PrimaryPart`.
  - Impact: valid custom characters with `HumanoidRootPart` and `Humanoid` but nil `PrimaryPart` can be skipped.
  - Fix direction: check `HumanoidRootPart` directly or set `PrimaryPart` to HRP as part of character readiness.

- [ ] Fix profile-loaded readiness race.
  - Current code: `DataService` fires `ProfileLoaded` once through `ServerEventBus`; `RoundService` only receives it if already subscribed.
  - Impact: startup ordering can lose the fact and cause players to fail readiness.
  - Fix direction: store loaded-profile state in `DataService` for queries, or make readiness facts/events sticky and replayable.

- [ ] Harden teleport and match admission validation.
  - Current code: `TeleportDataValidator.fillLoadouts` indexes `v.Power` without proving each loadout entry is a table.
  - Current code: duplicate user ids and non-positive user ids are accepted in production teleport data.
  - Current code: after a `RoundSystem` exists, later joiners in `WaitingForPlayers` are not checked against the original match id and roster before `RegisterPlayer`.
  - Impact: malformed loadouts can crash validation; duplicate/non-real users can create unfillable or broken matches; non-roster players can be admitted into a reserved match.
  - Fix direction: validate loadout entry shape before indexing, reject duplicate and non-positive user ids for production paths, and require matching match id plus original-roster membership for late joiners.

- [ ] Fix reward/stat accumulation across rounds.
  - Current code: `PlayerState:Reset()` zeros kills every intermission; return payload reads current kills only.
  - Impact: match rewards only count the final round's kills.
  - Fix direction: track cumulative match stats separately from per-round reset state, or snapshot each round's stats into `_roundResults` and compute rewards from cumulative data.

- [ ] Include match action IDs in return rewards.
  - Current code: `TeleportUtility.buildReturnPayload` accepts `matchId`, but `RoundOrchestrator` calls it without passing one.
  - Impact: every reward delta `actionId` is nil, weakening idempotency in lobby reward application.
  - Fix direction: pass `system:GetMatchId()` or metadata match id into `buildReturnPayload`.

- [ ] Fix spectator snapshot shape mismatch.
  - Current code: `PlayerState:Serialize()` returns real `Player` instances; `Spectate.derive` validates `entry.player` as a Lua table with `UserId`.
  - Impact: spectate derivation rejects active snapshots and camera spectating fails.
  - Fix direction: serialize primitive player fields, or update validation/derive logic to accept `Player` instances intentionally.

- [ ] Fix first `RoundActive` broadcast using stale round number.
  - Current code: `RoundSystem:_onStateChanged` broadcasts before `RoundOrchestrator.enterRoundActive` increments `_roundNumber`.
  - Impact: clients can see `RoundActive` with the previous round number, often `0`.
  - Fix direction: increment/update round state before broadcasting `RoundActive`, or make the broadcast happen after the state handler mutates round counters.

- [ ] Add player setup guards to non-data executors.
  - Current code: gun, knife, power, and round executors connect `PlayerAdded` and loop `Players:GetPlayers()` without the handled guard used by `DataService`.
  - Impact: a join between connect and loop can double-register remotes/listeners/round state.
  - Fix direction: add weak-key handled guards around `setupPlayer` in each executor.

## P1 Incomplete Systems

- [ ] Finish reconnect join-flow integration.
  - Current code: `ReconnectService` can write/validate tickets and `RoundSystem:RegisterReconnect` exists, but `RoundService.executor` never detects reconnect teleport data, calls `ValidateReconnect`, calls `RegisterReconnect`, or returns rejected reconnects to lobby.
  - Impact: disconnect tickets are mostly dead code; rejoining players follow the normal registration path instead of reconnect recovery.
  - Fix direction: add reconnect branch in player setup before normal teleport validation, validate expected match id, call `RegisterReconnect`, and return/kick on rejected tickets.

- [ ] Implement gun ammo/reload semantics.
  - Current code: `ReloadAction.serverExecute` is empty and there is no ammo, magazine, reserve, reload lock, or no-ammo shoot gate.
  - Impact: reload is only a cooldown/animation placeholder; shooting has no ammunition model.
  - Fix direction: define gun ammo state in shared/server types, decrement on shoot, reject empty shots, refill on reload completion, and surface state to the client if UI needs it.

- [ ] Make timed power effects round-safe and overlap-safe.
  - Current code: many powers use `task.delay` to restore humanoid properties or attributes; `RoundScope.Cleanup()` only destroys registered instances.
  - Impact: speed/cooldown/combat/shield/visibility effects can survive round transitions or clear another overlapping effect's attribute.
  - Fix direction: register effect cleanup callbacks or tokens with round scope, use per-effect handles/reference counts for shared attributes, and cancel/revert on death, disconnect, and non-active round transitions.

- [ ] Finish Blinding as an authoritative projectile.
  - Current code: Blinding uses an unanchored physics part with `AssemblyLinearVelocity`, no raycast travel, no blocking-geometry handling, and no line-of-sight check for aim assist.
  - Impact: projectile can pass through walls and gravity can pull it below an aim-assisted target.
  - Fix direction: use a deterministic raycast/constraint projectile like knife throws, stop on blocking geometry, and require line of sight for aim assist.

- [ ] Harden FakeClone.
  - Current code: `char:Clone()` is used without temporarily enabling `Archivable`, and clone is not nil-checked before descendants are accessed.
  - Impact: standard characters can fail to clone and error the power.
  - Fix direction: save/restore `char.Archivable`, nil-check the clone, and fail gracefully.

- [ ] Handle slow Humanoid replication in power input.
  - Current code: `PowerController/Input.attachCharacter` calls `FindFirstChildOfClass("Humanoid")` immediately on `CharacterAdded`.
  - Impact: if Humanoid appears shortly after `CharacterAdded`, ability UI can stay disabled until a later character event.
  - Fix direction: use `WaitForChild("Humanoid", timeout)` or listen for child insertion before marking the player not alive.

- [ ] Align loadout/equipment persistence with runtime use.
  - Current code: `DataService` stores `Knives` and `Guns` as boolean sets only; current round weapon distribution is driven by teleport loadout names.
  - Current docs still describe equipped knife APIs that are not implemented in `DataService`.
  - Impact: persistent ownership/equipped selection and round loadout resolution are not consolidated.
  - Fix direction: decide whether equipped weapons live in DataService, lobby teleport metadata, or both; then implement one canonical schema and update docs.

- [ ] Decide and gate `GlobalConfigs.TEST_MODE`.
  - Current code: `TEST_MODE = true`, so round setup uses template data, teleport-out is skipped, and reconnect returns are skipped.
  - Impact: production behavior is disabled unless this config is changed manually.
  - Fix direction: add an environment-specific config strategy or an explicit release checklist item that prevents shipping with test mode on.

## P2 Cleanup/Polish

- [ ] Tighten map spawn validation.
  - Current code: `MapValidator` counts descendants by spawn name only; runtime later assumes spawn entries have `CFrame`.
  - Impact: non-`BasePart` spawn descendants can pass validation and fail during positioning.
  - Fix direction: count only `BasePart` spawns, and make the required count match selected game mode instead of always `MAX_PLAYERS_PER_TEAM` when appropriate.

- [ ] Tighten weapon template validation.
  - Current code: `ensureKnifeHitbox` trusts any child named `Hitbox`; stab later casts it as `BasePart`.
  - Current code: `ensureGunShootPoint` accepts any child named `ShootPoint`; client shooting assumes `WorldCFrame`, which is an attachment shape.
  - Impact: malformed templates can crash or abort runtime combat.
  - Fix direction: require `Hitbox` to be a `BasePart`, require `ShootPoint` or renamed `ShootAttachment` to be an `Attachment`, and replace/fail invalid children deterministically.

- [ ] Update stale configuration docs.
  - Current docs reference old spawn names (`RedPart`/`BluePart`), old player counts, old `CHARACTER_LOAD_TIMEOUT`, old `LOBBY_PLACE_ID = 0`, and old knife equip APIs.
  - Impact: returning to the project from docs leads to wrong setup and expectations.
  - Fix direction: update `documentation.md` to match current `Round.Configs`, `Map.Configs`, weapon distribution, powers, reconnect, and test mode behavior.

- [ ] Decide what to do with deleted historical specs/plans.
  - Current worktree deletes many `docs/superpowers/plans` and `docs/superpowers/specs` files.
  - Impact: useful implementation context may be lost unless this deletion is intentional.
  - Fix direction: either restore/archive the relevant docs or confirm their removal in a cleanup commit.

- [ ] Clean up placeholder/debug utilities.
  - Current code has empty trace functions and `DebugUtility.Print` ignores messages even when enabled.
  - Impact: debug flags do not produce diagnostics, making complex round/combat bugs harder to inspect.
  - Fix direction: either remove dead debug hooks or make the utility actually print under gated debug configs.

- [ ] Fill or deliberately remove blank content hooks.
  - Current code contains blank sound ids and missing knife stab/idle animation ids.
  - Impact: combat feedback is incomplete if these are intended to ship.
  - Fix direction: add real ids in config or document that these hooks are intentionally empty.

## Testing Debt

- [ ] Restore or replace the deleted test suite.
  - Deleted in the working tree: `src/Client/Tests/WeaponSystemTests.lua`, power integration tests, round readiness/system tests, weapon distributor tests, animation profile tests, gun/knife payload and state machine tests, map validator tests, and spectate derive tests.
  - Impact: most high-risk systems now have no repo-local regression coverage.
  - Fix direction: restore relevant tests from git history or recreate focused tests around current behavior.

- [ ] Add payload/security regression tests.
  - Cover malformed gun/knife/power remotes, invalid sequence IDs, wrong payload types, spoofed remotes, and state override responses.

- [ ] Add round lifecycle regression tests.
  - Cover profile-loaded replay, readiness without `PrimaryPart`, late character load timeout, positioning finalization, stale `RoundActive` round number, non-roster joins, duplicate/non-positive user ids, disconnect/reconnect, and reward payloads.

- [ ] Add combat/power regression tests.
  - Cover shield consumption for stab/throw/shoot, max stab distance, ammo/reload once implemented, Blinding wall/LOS behavior, FakeClone clone failure, timed power cleanup, overlapping buffs, and combat disabled during dash.

- [ ] Add spectate/client state tests.
  - Cover snapshot shape accepted by `Spectate.derive`, target ordering, dead/skipped/disconnected local player behavior, and camera restoration.

- [ ] Add manual Studio smoke scenarios.
  - 1v1 full match, multi-round rewards, intermission weapon input, reconnect ticket flow, each power once, malformed asset instance types, and player join/leave during waiting/preparing/active states.

## Excluded From Todo By Assumption

- Missing external Studio-created instances are not tracked here. The `NetworkRouter Can Hang Forever On Boot` item from `docs/FoundBugs.md` is intentionally excluded under the current rule that `ReplicatedStorage.Remotes` exists if code references it.

## Verification

- `argon build -o .bg-shell/audit-build.rbxlx -x -y` succeeded on 2026-05-18.
- Build warning observed: `ServerPackages` path from `default.project.json` does not exist. This is not treated as a missing runtime asset issue, but the project mapping should be cleaned up if the path is no longer needed.
- Removed generated `.bg-shell/audit-build.rbxlx` after the check.
- Studio test execution was not run from this pass because the current working tree has no `*.test.lua` files available.
