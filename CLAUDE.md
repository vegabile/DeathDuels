# CLAUDE.md

## Engineering constraints (non-negotiable)
- Make the SMALLEST change that satisfies the requirement. Minimal diff, always.
- No new abstractions, layers, interfaces, config options, or generality unless
  I explicitly ask. YAGNI is the default.
- Do not refactor, rename, or touch code outside the specific change requested.
- Do not add speculative error handling, logging, or "robustness" I didn't ask for.
- Prefer fewer lines. A 3-line fix beats a 30-line "proper" one.
- If the diff comes out larger than the obvious hand-written fix, that's a
  failure — stop and reconsider, don't ship the sprawl.
- NEVER "harden" ANYTHING, UNLESS I tell you to. NEVER even consider it.

## Plan before executing
- For any multi-step, multi-file, or multi-agent task: present a short plan and
  WAIT for my approval before writing code or spawning anything.
- Never spin up subagents or start a workflow without showing the plan first.
- If a change is structural or has wide blast radius, surface the design choice
  in ONE sentence and wait. Do not implement it yet.

## Autonomy (only AFTER the plan is approved)
- Once a plan is approved, work continuously to completion. Do NOT stop mid-task
  to ask "what should I do here?"
- On routine implementation choices, pick the option consistent with the
  existing code, proceed, and note the assumption in your final summary.
- Only interrupt me for: (a) destructive or irreversible actions, or (b) a
  genuine architectural fork not already covered by the approved plan.
- Never stop for permission on reversible, in-branch changes.

## Verification is the bar
- Behavior is defined by tests, not by your judgment that it "looks right."
- Where a test can pin the intended behavior, write or confirm it BEFORE the fix.
- Do not write tests that merely rubber-stamp whatever you happened to build.
- "Done" means: typecheck + relevant tests pass, and you have shown me the diff.

## Git workflow
- Always work on a separate branch. Never commit directly to master/main.
- Split work into commits grouped by logical task — one coherent change per commit.
- Open a PR when the work is done. A PR is a group of related commits.
- Keep PRs under ~500 lines of diff. If the work exceeds that, split it across
  multiple PRs, each independently reviewable.