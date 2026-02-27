Less is always more. If you can write it in less, you should.

Large sweeping changes should be avoided. Opt for surgical removals/additions.

Always pre-define contracts & interfaces before writing anything

Validate data at boundaries. Never trust input from external sources — parse, don't assume.

Prefer boring, well-known technology. Exotic dependencies are a liability.

Tests prove the contract works, not that the implementation exists. Test behavior, not internals.
One file, one responsibility. If a file is doing two things, split it.

Names are documentation. If you need a comment to explain what something does, rename it.
Dead code is worse than no code. Delete aggressively.

Side effects belong at the edges. Keep core logic pure and deterministic.

Configuration lives in one place. Never scatter env vars or magic strings across files.

NEVER blindly/silently fail or return. If something stops it from performing the logic, or that there's a non happy-path case, make sure the reason is clearly articulated via "Warn"

Depend on contracts, not implementations. Inject dependencies through interfaces so your code never couples to a specific source or service.

RUTHLESSLY PURGE uncertainty. If its not CRYSTAL CLEAR, YOU EITHER FIX IT OR REMOVE IT

After you make changes, follow the CI/CD framework by writing tests for it and testing it alongside everything else in Lune.

Example:
function handleButtonPressed(Button : TextButton) -- Passed in
handleButtonPressed(nil) -- FOR NOW