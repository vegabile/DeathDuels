# `MATCH_WIN_QUEST_KEY` — match-win quest contract

This documents a non-obvious cross-place contract previously captured in an inline
comment in `src/Shared/Round/Configs.lua`.

## What it is

`Configs.MATCH_WIN_QUEST_KEY = "MatchWins"` is the quest requirement key that the **lobby**
increments by `1` for an overall **match** win. It drives the "Triple Threat" quest
(= win 3 matches).

## The contract

- The game emits this key in the return-teleport payload's `quest` delta for **every player
  on the winning team** (see `TeleportUtility.buildReturnPayload` / `buildQuestDelta` in
  `src/Server/RoundService/TeleportUtility.lua`). The lobby applies the `quest` map as
  *requirement-key → increment*, so no lobby code change is needed **as long as the key
  matches**.
- The string **must equal the lobby's match-win quest requirement id**. It is deliberately
  isolated to this single constant: if the lobby uses a different name (e.g. `"Wins"`),
  change **only** `MATCH_WIN_QUEST_KEY`.

## Notes

- This is per-**match**, distinct from `RoundWins` / per-round streak quests, which are
  per-round.
- A match win is credited to every player on the winning team present in the payload,
  including a player who disconnected late. The winning team is resolved in
  `RoundOrchestrator.enterTeleportingOut` (which falls back to the deciding round result on a
  forfeit/walkover, where `WinConditionEvaluator.isGameOver` reports no winner yet).
