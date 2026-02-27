# Architecture

## Overview
BrainrotRNG. This is a Roblox game, about rolling a dice for "Brainrots". These "Brainrots" are then sold for money to upgrade the roller, thereby allowing you to roll better brainrots which sell for more.

## Domain Map
The system is organized into business domains. Each domain is self-contained.

PlayerData - All the inventory and currency, plus whatever level they're at, their odds, etc
RollHandler - Handles all the rolling

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