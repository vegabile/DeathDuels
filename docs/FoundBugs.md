Bug Name: NetworkRouter Can Hang Forever On Boot
  Cause: NetworkRouter waits for ReplicatedStorage.Remotes, but the
  repo does not define a Remotes folder.
  How to reproduce: Sync a clean copy of this project into Studio
  without manually adding ReplicatedStorage.Remotes; start the server.
  Server/client scripts that require NetworkRouter hang at startup.
  Confidence in reproduction: High on a clean synced place; medium if
  your Studio place has unsynced assets.
  Recommended fix: Create the Remotes folder in code/project config or
  have NetworkRouter create it on the server.

  Bug Name: Spectate State Rejects Real Player Instances
  Cause: Spectate validation expects entry.player to be a Lua table,
  but round snapshots serialize actual Player Instances.
  How to reproduce: Start a round, kill the local player, and watch
  client output. Spectate derivation rejects snapshot.playerStates[n];
  camera never enters valid spectate state.
  Confidence in reproduction: High.
  Recommended fix: Serialize userId/name primitives in
  PlayerState:Serialize, or validate typeof(entry.player) ==
  "Instance".

  Bug Name: Match Rewards Only Count The Final Round’s Kills
  Cause: PlayerState:Reset() zeros kills every intermission, while
  return payload rewards read only current state:GetStat("kills").
  How to reproduce: In a multi-round match, get kills in round 1, then
  finish the match. Inspect the teleport return payload; earlier-round
  kills are gone.
  Confidence in reproduction: High.
  Recommended fix: Keep cumulative match stats separate from per-round
  status resets, or snapshot round stats into _roundResults.

  Bug Name: Positioning Timeout Leaves Phantom Alive Players
  Cause: The outer positioning timeout treats Alive as terminal even if
  positionedThisRound == false; late load tasks can also skip/position
  players after finalization without rechecking state.
  How to reproduce: On round 2+, force a player’s character to appear
  without HRP/Humanoid for longer than POSITIONING_OUTER_TIMEOUT. They
  remain counted alive while unpositioned, or mutate after the round
  has finalized.
  Confidence in reproduction: High with a controlled test rig.
  Recommended fix: Track a pending-positioning state, force-skip based
  on positionedThisRound, and guard late tasks with current round/state
  checks.

  Bug Name: Valid Characters Can Be Force-Skipped If PrimaryPart Is Nil
  Cause: readiness records HRP/Humanoid facts, then isComplete
  additionally requires player.Character.PrimaryPart.
  How to reproduce: Use a custom character with HumanoidRootPart and
  Humanoid, but no Model.PrimaryPart; join a match. The character loads
  but readiness never completes.
  Confidence in reproduction: High for custom rigs; depends on default
  rig setup.
  Recommended fix: Check for HumanoidRootPart directly, or explicitly
  set character.PrimaryPart = HumanoidRootPart.

  Bug Name: Stab Can Kill Through Shield
  Cause: Heartbeat stab damage respects ShieldActive, but the .Touched
  fallback calls humanoid.Health = 0 and bypasses shield handling.
  How to reproduce: Give victim ShieldActive = true, have them enter
  the knife hitbox during a stab window, and observe that the touched
  path can kill instead of consuming shield.
  Confidence in reproduction: High, timing-sensitive but real.
  Recommended fix: Route touched hits through the same shield-aware
  damage function as heartbeat hits; use TakeDamage.

  Bug Name: Stab Distance Limit Is Not Applied In Heartbeat Path
  Cause: heartbeat stab logic references attackerRoot without defining
  it in that scope, so the MAX_STAB_DISTANCE guard is skipped.
  How to reproduce: Give a knife an oversized/manual Hitbox; stand
  farther than MAX_STAB_DISTANCE; stab. Heartbeat overlap can still
  damage.
  Confidence in reproduction: High with a malformed/oversized hitbox.
  Recommended fix: Define attacker root inside the heartbeat callback
  or shared hit-processing function.

  Bug Name: Blinding Projectile Passes Through Walls
  Cause: projectile is non-colliding and touched handling ignores non-
  player geometry; aim assist also does no line-of-sight check.
  How to reproduce: Put an enemy behind a wall in front of the caster
  and activate Blinding. The projectile can pass through the wall and
  blind them.
  Confidence in reproduction: High.
  Recommended fix: Raycast projectile travel, destroy on blocking
  geometry, and require line of sight for aim assist.

  Bug Name: Fake Clone Can Crash On Real Characters
  Cause: char:Clone() is used without ensuring char.Archivable = true;
  real player characters commonly are not cloneable by default.
  How to reproduce: Equip fakeclone on a normal player character and
  activate it. If Character.Archivable is false, clone is nil and the
  power errors.
  Confidence in reproduction: High in standard Roblox character setups.
  Recommended fix: Temporarily set char.Archivable = true, clone, then
  restore the original value and nil-check the clone.

  Bug Name: Malformed Weapon Remote Payloads Error Instead Of Rejecting
  Cause: Gun/knife services index payload.sequenceId after validation
  fails, and knife logs payload.desiredAction before validation.
  How to reproduce: From an exploit/local test client, fire
  GunAction_<userId> or KnifeAction_<userId> with a number/string
  payload during RoundActive. Server callback errors instead of cleanly
  rejecting.
  Confidence in reproduction: High.
  Recommended fix: Never index raw payload unless type(payload) ==
  "table"; use a safe sequence sanitizer like Power payloads do.

  Bug Name: TeleportDataValidator Crashes On Non-Table Loadout Entries
  Cause: fillLoadouts iterates loadouts and immediately indexes v.Power
  without checking type(v) == "table".
  How to reproduce: Teleport into a match with loadouts = { ["123"] =
  5 }. Validation errors instead of returning false.
  Confidence in reproduction: High.
  Recommended fix: Validate each loadout value shape before indexing;
  default or reject malformed entries.

  Bug Name: Duplicate UserIds Can Create Broken 1v0 Matches
  Cause: teleport validation does not reject the same UserId appearing
  on both teams; expected player count counts duplicates, team lookup
  overwrites.
  How to reproduce: Send teleport data with the same player in
  teamOnePlayers and teamTwoPlayers. After wait timeout, the match
  starts underfilled and can immediately award a round.
  Confidence in reproduction: High.
  Recommended fix: Reject duplicate UserIds across the combined roster.

  Bug Name: Map Spawn Validation Allows Non-Parts
  Cause: MapValidator counts descendants by name only; runtime later
  assumes each spawn has CFrame.
  How to reproduce: Put Folders/Models named RedSpawn and BlueSpawn in
  a registered map. Validation can pass, then positioning errors/skips
  players.
  Confidence in reproduction: High.
  Recommended fix: Require spawn descendants to be BasePart.

  Bug Name: Gun ShootPoint Validation Allows Wrong Instance Type
  Cause: weapon setup accepts any child named ShootPoint; client
  shooting assumes it has WorldCFrame, which is true for Attachments,
  not arbitrary Instances.
  How to reproduce: Put a Part or Folder named ShootPoint under a gun
  Handle, equip it, and shoot. Client errors or aborts.
  Confidence in reproduction: High.
  Recommended fix: Require ShootPoint/ShootAttachment to be an
  Attachment; replace invalid children or fail weapon validation.

  Bug Name: Weapon Inputs Can Lock Client Outside RoundActive
  Cause: Client weapon controllers listen for RoundStateChanged, but
  client only fires RoundUpdate; performAction also has no round-state
  gate, and server rejects inactive-round actions without a
  StateOverride.
  How to reproduce: End a round while holding/equipped weapon, press
  shoot/stab/throw during intermission, then try acting as the next
  round starts.
  Confidence in reproduction: High.
  Recommended fix: Fire client RoundStateChanged from RoundUpdate,
  track roundActive in weapon controllers, and send corrective
  responses on server inactive-state rejects.

  Bug Name: First RoundActive Snapshot Has Stale Round Number
  Cause: RoundSystem:_onStateChanged broadcasts before
  RoundOrchestrator.enterRoundActive increments _roundNumber.
  How to reproduce: Log client RoundUpdate snapshots at match start;
  the first RoundActive snapshot reports the previous round number,
  often 0.
  Confidence in reproduction: High.
  Recommended fix: Move round-number increment before the state
  broadcast, or make RoundActive entry update state before
  broadcasting.

  Bug Name: Waiting Match Accepts Non-Roster Players
  Cause: Once roundSystem exists, later joiners in WaitingForPlayers
  are validated against their own teleport data but not checked against
  the original match roster or matchId. Missing team falls through to
  dynamic assignment.
  How to reproduce: Start a reserved match waiting for player B;
  teleport player C into the same server with any valid match-shaped
  teleport data before the wait expires. C is admitted and assigned.
  Confidence in reproduction: High with a controlled teleport test.
  Recommended fix: For existing matches, require matching matchId and
  require player.UserId in the original metadata roster.

  Bug Name: Non-Positive UserIds Create Unfillable Matches
  Cause: TeleportDataValidator accepts UserId = 0 or negative numbers.
  Those entries count toward expected players but can never join as
  real players.
  How to reproduce: Send production teleport data with teamTwoPlayers =
  { { UserId = 0, Name = "X" } }; after wait timeout, the match starts
  underfilled.
  Confidence in reproduction: High.
  Recommended fix: Reject UserId <= 0 in production teleport
  validation; update test-mode fake data separately.

  Bug Name: ProfileLoaded Readiness Fact Can Be Lost
  Cause: DataService fires ServerEventBus:Fire("ProfileLoaded") once,
  but RoundService only receives it if already subscribed; the bus has
  no replay/current-state storage.
  How to reproduce: Delay RoundService executor subscription until
  after DataService loads a player profile; the player never records
  ProfileLoaded and is skipped after readiness timeout.
  Confidence in reproduction: High with forced startup ordering, medium
  naturally.
  Recommended fix: Store profile-loaded state in DataService and let
  RoundService query it, or make readiness facts sticky/replayed.

  Bug Name: Combat Services Can Miss RoundActive
  Cause: Gun, knife, and power services cache round state only from
  one-shot RoundStateChanged events. If they subscribe after the event,
  currentRoundState stays "".
  How to reproduce: Delay GunService/KnifeService/PowerService module
  load until after RoundActive, then try shooting/using powers. Server
  rejects actions as state "".
  Confidence in reproduction: High with forced startup ordering, medium
  naturally.
  Recommended fix: Keep current round state in a queryable
  RoundService/ServerEventBus store and initialize listeners from that
  value.

  Bug Name: Bad Manual Knife Hitbox Crashes Stab
  Cause: ensureKnifeHitbox skips generation if any child named Hitbox
  exists, without requiring a BasePart; stab later passes it to
  workspace:GetPartsInPart.
  How to reproduce: Put a Folder named Hitbox in a knife template,
  equip it, and stab. Server errors when overlap runs.
  Confidence in reproduction: High.
  Recommended fix: Validate existing Hitbox is a BasePart, or delete/
  replace invalid hitboxes during weapon init.

  Bug Name: Blinding Projectile Drops Below Aim-Assisted Target
  Cause: Blinding uses AssemblyLinearVelocity on an unanchored physics
  part with no anti-gravity force, so gravity pulls it down while aim
  assist computes a straight direction.
  How to reproduce: Stand 40+ studs from an enemy at the same height
  and activate Blinding; projectile visibly falls below the target and
  misses.
  Confidence in reproduction: High.
  Recommended fix: Use LinearVelocity/constraint force like knife
  projectiles, raycast travel, or compensate for gravity.

  Bug Name: Ability UI Can Stay Disabled On Slow Humanoid Replication
  Cause: PowerController/Input.attachCharacter uses
  FindFirstChildOfClass("Humanoid") immediately on CharacterAdded; if
  Humanoid appears later, alive remains false with no retry.
  How to reproduce: Use a character spawn path where Humanoid is
  inserted after CharacterAdded; AbilityUI never appears despite
  RoundActive and equipped power.
  Confidence in reproduction: Medium-high; rig/load-order dependent.
  Recommended fix: WaitForChild("Humanoid", timeout) and/or listen for
  Humanoid child insertion before marking not alive.

  Bug Name: Startup Player Setup Can Double-Register Players
  Cause: Gun, knife, and round executors use
  PlayerAdded:Connect(setupPlayer) plus a GetPlayers() loop without the
  handled guard used by DataService. A join between those two steps can
  run setup twice.
  How to reproduce: Force a yield between connecting PlayerAdded and
  iterating GetPlayers, then join a player. Weapon remotes/listeners or
  round registration duplicate.
  Confidence in reproduction: High with forced timing, low-medium
  naturally.
  Recommended fix: Add per-player handled guards to those executors.

  Bug Name: Return Payload Never Includes Reward Action IDs
  Cause: TeleportUtility.buildReturnPayload accepts matchId, but
  RoundOrchestrator calls it without passing one, so every
  delta[userId].actionId is nil.
  How to reproduce: Finish a match and inspect teleport payload; reward
  deltas have nil actionId.
  Confidence in reproduction: High.
  Recommended fix: Pass system:GetMatchId() or metadata matchId into
  buildReturnPayload.