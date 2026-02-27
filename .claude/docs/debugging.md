If I call /rubber-duck, essentially what you should do is read thru the codebase, and then I can talk about the codebase like youre a rubber duck, and you respond with any contradictions or ideas on why a bug might be.

/bisect [symptom] — you describe the bug, Claude walks you through a structured halving process, asking yes/no questions to narrow the location

/suspect — Claude reads the codebase and outputs a ranked list of most likely bug locations based on complexity, coupling, or common Lua/Roblox pitfalls

/trace [function or system] — Claude reads that specific part of the codebase and produces a step-by-step execution walkthrough, highlighting assumptions that could break

/oracle [bug description] — Claude writes you a print-statement diagnostic script you can paste in to confirm or deny the bug in specific places

/log [bug description] - After solving, log it in bugs.md