# Plan: Progressive TeleportMetadata Loading During Player Stream-In

## Context
- **Current State**: TeleportMetadata is passed via TeleportOptions but NOT accessed on destination server
- **Goal**: Load all metadata progressively as players stream into the game, avoiding bottlenecks
- **Research Base**: Roblox documentation on streaming, TeleportData, PlayerAdded/CharacterAdded patterns

---

## Key Insights from Research

### 1. TeleportData Access Timing
- `player:GetJoinData()` returns `{TeleportData = {...}, CharacterAppearanceLoaded = bool}`
- This is available **immediately when PlayerAdded fires** (no special wait needed)
- TeleportData is **unencrypted** — only use for non-sensitive metadata

### 2. Player Streaming Mechanics
- Players render content around them based on `StreamingMinRadius` / `StreamingTargetRadius`
- Instance streaming happens **in parallel with data loading** — not blocked by it
- Default player join time: ~5 seconds (respawn delay) but actual content visibility is faster

### 3. Correct PlayerAdded/CharacterAdded Pattern
The current codebase has **race condition risk**. Correct pattern:
```lua
local function onCharacter(character) ... end
local function onPlayer(player)
  if player.Character then
    task.defer(onCharacter, player.Character)  -- Already has character
  end
  player.CharacterAdded:Connect(onCharacter)   -- Future characters
end

for _, player in game.Players:GetPlayers() do
  task.defer(onPlayer, player)
end
game.Players.PlayerAdded:Connect(onPlayer)
```
Using `task.defer()` prevents race conditions during rapid joins.

---

## Implementation Plan

### Phase 1: Data Retrieval on PlayerAdded (Non-Blocking)
**File**: Create `src/Server/RoundService/TeleportMetadataService.lua`

**Responsibilities**:
- Extract `TeleportData` from `player:GetJoinData()` on PlayerAdded
- Validate using existing `TeleportDataValidator`
- Store metadata in a lightweight lookup table (not in profiles)
- Expose synchronous getter: `GetTeamForPlayer(player)` → `1|2|nil`

**Key behavior**:
- No blocking waits — extract and store immediately
- Return early if data missing (graceful fallback)
- Use `warn()` for validation failures (never silent fail)

---

### Phase 2: Lazy Character Initialization
**File**: Modify `src/Server/RoundService/` player setup handlers

**Integrate with existing flow**:
1. **DataService.OnPlayerAdded** (existing) → loads profile asynchronously
2. **TeleportMetadataService.GetTeamForPlayer(player)** (new) → returns team assignment immediately
3. **CharacterAdded handler** (new) → applies team to character/spawns at correct location
4. **GunService/KnifeService.OnPlayerAdded** (existing) → use cached profile data

**Sequence**:
```
PlayerAdded
├─ TeleportMetadataService extracts metadata
├─ DataService loads profile (async, non-blocking)
└─ CharacterAdded (when character spawns)
   ├─ Verify player.Character.Parent (ensure fully loaded)
   ├─ Apply team assignment from metadata
   ├─ Spawn at team-specific location
   ├─ Wait for profile if not yet loaded (profile loads in parallel)
   └─ Initialize weapons from profile
```

---

### Phase 3: Optional — Session State via MemoryStore (Future Enhancement)
**When to use**: If you need to track interim state (buffs, matchmaking status) that expires

**Pattern** (not required for MVP):
```lua
MemoryStoreService:CreateQueue("QueueName")
-- On teleport out: queue:AddAsync(player.UserId, sessionState, 60*5)
-- On arrive: queue:ReadAsync() to get session data if exists
```

---

## Detailed Changes

### 1. Create TeleportMetadataService
```
Purpose: Extract, validate, and serve teleport metadata
Location: src/Server/RoundService/TeleportMetadataService.lua
Exports:
  - StorePlayerTeam(player, team)
  - GetTeamForPlayer(player) → 1|2|nil
  - GetAllTeamAssignments() → {player → team}
  - ClearPlayer(player)
```

**Contract**:
- Team is `1` or `2`, never `nil` after a valid PlayerAdded
- If metadata missing or invalid, return `nil` and warn
- Synchronous (no async waits)

---

### 2. Update PlayerAdded Flow (DataService.executor)
In `src/Server/DataService/executor.server.lua`:
```lua
-- After DataService module loads:
local TeleportMetadataService = require(script.Parent.Parent.RoundService.TeleportMetadataService)

game.Players.PlayerAdded:Connect(function(player)
  -- Parallel: extract metadata immediately
  local joinData = player:GetJoinData()
  if joinData and joinData.TeleportData then
    local isValid, err = TeleportDataValidator.validate(joinData.TeleportData)
    if isValid then
      -- Store team assignment (fast synchronous operation)
      local metadata = joinData.TeleportData
      TeleportMetadataService.StorePlayerTeam(player, metadata.teamOnePlayers, metadata.teamTwoPlayers)
    else
      warn(`[DataService] Invalid teleport data for {player.Name}: {err}`)
    end
  end
  
  -- Existing flow continues: profile loads asynchronously
  DataService.OnPlayerAdded(player)
end)
```

---

### 3. Create RoundManager (Coordinates Everything)
**File**: `src/Server/RoundService/RoundManager.lua`

**Responsibilities**:
- Hooks into PlayerAdded AFTER metadata extracted
- Calls `TeleportMetadataService.GetTeamForPlayer()` to assign spawns
- Waits for character, verifies full load with `repeat task.wait() until char.Parent`
- Ensures profile is ready before initializing weapons (with timeout)

**Example flow**:
```lua
local function setupPlayerForRound(player)
  local team = TeleportMetadataService.GetTeamForPlayer(player)
  if not team then
    warn(`[RoundManager] No team assigned for {player.Name}`)
    return
  end
  
  -- Wait for character with proper verification
  local char = player.Character
  if char and char.Parent then
    task.defer(onCharacterSpawned, player, char, team)
  end
  
  player.CharacterAdded:Connect(function(newChar)
    onCharacterSpawned(player, newChar, team)
  end)
end

-- Handle existing players
for _, player in game.Players:GetPlayers() do
  task.defer(setupPlayerForRound, player)
end
game.Players.PlayerAdded:Connect(setupPlayerForRound)
```

---

### 4. Update TeleportDataValidator
No changes needed — already validates structure. Just ensure it's imported where needed.

---

## Data Flow Diagram

```
Teleport initiated (Lobby)
  ↓
TeleportOptions:SetTeleportData(metadata)
  ↓
TeleportPartyAsync(destinationPlace, players, teleportData)
  ↓
═══ DESTINATION PLACE ═══
  ↓
PlayerAdded fires
  ├─ GetJoinData() extracts metadata [IMMEDIATE]
  ├─ TeleportMetadataService.StorePlayerTeam() [IMMEDIATE]
  ├─ DataService.OnPlayerAdded() [ASYNC - profile loads in background]
  └─ CharacterAdded fires (when character spawns)
      ├─ Wait for char.Parent [BRIEF]
      ├─ Get team from TeleportMetadataService [IMMEDIATE]
      ├─ Spawn at team location [IMMEDIATE]
      └─ If profile ready: initialize weapons [CONCURRENT WITH STREAMING]
```

---

## Testing Strategy

1. **Unit Tests**:
   - TeleportMetadataService extraction with valid/invalid data
   - Team assignment lookup correctness

2. **Integration Tests**:
   - Simulate PlayerAdded → CharacterAdded → ProfileLoaded sequence
   - Verify teams are assigned before weapons initialize
   - Confirm no blocking waits during join

3. **Performance Tests**:
   - Measure time from teleport to character spawn
   - Measure time from spawn to first weapon available
   - Profile for no frame drops during simultaneous joins

---

## Files to Create/Modify

### New Files
- `src/Server/RoundService/TeleportMetadataService.lua` — Service for metadata access
- `src/Server/RoundService/RoundManager.lua` — Orchestrates player round setup

### Modified Files
- `src/Server/DataService/executor.server.lua` — Hook metadata extraction on PlayerAdded
- `src/Server/RoundService/` — Any spawning/team initialization (if exists)

### No Changes Needed
- `TeleportDataValidator.lua` — Already correct, just reuse
- `TeleportUtility.lua` — Already handles the teleport send side

---

## Fallback Strategy (If Metadata Unavailable)
- Assign teams randomly or sequentially
- Warn but continue (never silently fail)
- Use default spawn point if no team location configured

---

## Success Criteria
✅ All metadata accessible within 1 frame of PlayerAdded
✅ No blocking waits during character spawn or player streaming  
✅ Teams assigned before weapon initialization  
✅ Graceful handling of missing/invalid metadata (warn, continue)  
✅ Parallel loading: profile loads while character renders  

