# Architecture

## Overview
Death Duels is a round-based PVP combat game on Roblox. Players spawn into arena maps and fight with guns or knives in 1v1 through 5v5 modes. Matches are short — kill or be killed, then back to the lobby. Winners earn coins, level up, and unlock cosmetics through a crate system with rarity tiers and pity mechanics. The lobby is the social and economic hub: open crates, equip loadouts, browse inventory, complete quests, and queue for the next fight. Progression runs on a prestige system with leaderboards tracking kills, wins, and rank. The core loop is queue, fight, earn, upgrade, repeat.

## Layer Model
Within each domain, code flows through layers in one direction only.
```
Types → Config → Repository → Service → Runtime → UI
```

- **Types** — Shared data shapes and enums. No imports from other layers.
- **Config** — Environment-driven configuration. Depends only on Types.
- **Repository** — Data access. Depends on Types and Config.
- **Service** — Business logic. Depends on Repository, Types, Config.
- **Runtime** — Orchestration, scheduling, background jobs. Depends on Service.
- **UI** — Presentation. Depends on Service and Types. Never imports Repository directly. (CLIENTSIDED)