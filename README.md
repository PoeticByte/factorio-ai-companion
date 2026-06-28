# Factorio AI Companion

<p align="right"><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>

AI companions for **Factorio 2.x** (incl. Space Age), driven by Claude through **MCP tools over
RCON**. Spawn a crew of robot companions — or autopilot your own character — that mine, craft,
build, fight, run logistics, and stand up **whole factories**. The crew can also **self-drive on a
headless dedicated server with no human present**, so Claude can both play *and* test itself.

> **v0.45.1** · 100 RCON commands kept **1:1** with 99 MCP tools · full history in
> [CHANGELOG.md](CHANGELOG.md).

---

## Table of contents

- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
  - [1. Clone & install dependencies](#1-clone--install-dependencies)
  - [2. Install the Factorio mod](#2-install-the-factorio-mod)
  - [3. Enable RCON](#3-enable-rcon)
  - [4. Host a game](#4-host-a-game)
  - [5. Connect the MCP server to Claude](#5-connect-the-mcp-server-to-claude)
- [Usage](#usage)
  - [In-game chat commands](#in-game-chat-commands)
  - [The reactive loop](#the-reactive-loop)
  - [Talking to the crew](#talking-to-the-crew)
  - [Headless / fully autonomous](#headless--fully-autonomous)
- [Tool reference](#tool-reference)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Versioning](#versioning)
- [Credits & license](#credits--license)

---

## Features

Three pillars:

### Pillar I — Autonomous colony (factory doctor → a whole factory)
- **Diagnose** bottlenecks and dead machines: unpowered / idle / out-of-fuel (`factory_analyze`,
  `factory_graph`).
- **Treat**: place the machine, set its recipe, wire it to power, fuel burners, and wire I/O
  inserters + chests (`factory_fix`, `factory_wire`).
- **Build** a complete working **station** for any recipe, a ratio'd **bank** of machines, lay
  **belts** (`build_station`, `build_bank`, `belt_connect`, `belt_link`).
- **`auto_factory <item>`** walks the recipe tree and builds the *entire* chain in one command,
  sized to your target rate, then auto-assigns couriers (`production_plan`, `recipe_deps`).

### Pillar II — Emergent collaboration
- **Plans** run as a parallel **dependency DAG**; the crew self-allocates each step to the best
  free companion (nearest / by specialty / capability-aware) (`plan_create`, `plan_status`,
  `plan_run`).
- **Standing roles**: guard, refueler, maintainer, **courier** (continuous A→B logistics), and
  **scout** (continuous map-learning) (`assign_role`, `assign_courier`, `roles`).
- **Task-board reservations** prevent two companions from grabbing the same resource
  (`reserve`, `release`, `reservations`).
- **Crew specialization** with `set_specialty` (miner / builder / hauler / fighter).

### Pillar III — A buddy that knows you
- **Persistent named locations** shown as map chart tags, plus preferences and notes that survive
  saves (`memory_remember`, `memory_recall`, `memory_forget`, `memory_goto`).
- **Auto-learns the map**: remembers ore patches and the nearest threats (`survey_remember`,
  `memory_nearest`).

### Core capabilities
- **Companions**: spawn / list / status / inventory / health / disappear; autopilot the player's
  own character with `attach_player` / `detach_player`.
- **Navigation**: pathfinding `move_to`, `move_follow`, `move_stop`.
- **Resources & crafting**: nearest/list/mine resources, pick/craft items, query recipes
  (`resource_*`, `item_*`), plus background skills `resource_mine_until` and `combat_until`.
- **Building & blueprints**: place/remove/rotate/fuel/fill machines, set recipes, mass-construct
  from blueprints (`building_*`, `blueprint_*`).
- **Logistics**: `haul` and `refuel` queues.
- **Combat crew**: attack / defend / flee / patrol / nest-clear / repair / `wololo`
  (`action_*`, `combat_until`).
- **Research**: read/set current research, progress, prerequisite chain (`research_*`,
  `tech_path`).
- **World awareness**: `world_scan`, `world_nearest`, `world_enemies`, `world_survey`, and a
  one-shot `overview`.

---

## How it works

```
Claude  ──MCP tools──►  MCP server (Bun, src/index.ts)  ──RCON──►  Factorio (ai-companion mod)
   ▲                                                                        │
   └───────────────── chat messages / status (RCON poll) ◄──────────────────┘
```

- The **mod** (`factorio-mod/`) exposes ~100 RCON commands and captures `/fac` chat.
- The **MCP server** (`src/`) wraps each command as a type-safe, validated MCP tool (kept 1:1 with
  the Lua side).
- **One orchestrator** manages ALL companions (id = 0, 1, 2, …). There are no separate subagents.

---

## Requirements

- [Factorio](https://factorio.com) **2.x** — must be **hosting multiplayer** (RCON only works
  while hosting, even for solo play), or run **headless** (see below).
- [Bun](https://bun.sh) (runtime for the MCP server and scripts).
- An MCP client (e.g. Claude Desktop / Claude Code) to drive the tools.

---

## Installation

### 1. Clone & install dependencies

```bash
git clone https://github.com/lveillard/factorio-ai-companion.git
cd factorio-ai-companion
bun install
```

### 2. Install the Factorio mod

Copy the contents of `factorio-mod/` into your Factorio mods folder as a folder named
`ai-companion`.

**Windows (Git Bash / PowerShell):**
```bash
cp -r factorio-mod/* "$APPDATA/Factorio/mods/ai-companion/"
```

**Linux:**
```bash
cp -r factorio-mod ~/.factorio/mods/ai-companion
```

**macOS:**
```bash
cp -r factorio-mod ~/Library/Application\ Support/factorio/mods/ai-companion
```

Then in Factorio: **Main Menu → Mods → enable "AI Companion" → restart**. Restart again any time
you update the mod files.

### 3. Enable RCON

Add the following to `config.ini` (no section header needed). On Windows it lives at
`%APPDATA%\Factorio\config\config.ini`:

```ini
local-rcon-socket=127.0.0.1:34198
local-rcon-password=factorio
```

These match the MCP server defaults (`FACTORIO_HOST=127.0.0.1`, `FACTORIO_RCON_PORT=34198`,
`FACTORIO_RCON_PASSWORD=factorio`). Override them via environment variables if you change the port
or password.

### 4. Host a game

**Multiplayer → Host New Game** (or **Load Game**). RCON only goes live while hosting — solo
single-player will **not** accept RCON connections.

### 5. Connect the MCP server to Claude

The repo ships an `.mcp.json` you can point your MCP client at:

```json
{
  "mcpServers": {
    "factorio-companion": {
      "command": "bun",
      "args": ["run", "src/index.ts"],
      "env": {
        "FACTORIO_HOST": "127.0.0.1",
        "FACTORIO_RCON_PORT": "34198",
        "FACTORIO_RCON_PASSWORD": "factorio"
      }
    }
  }
}
```

Use the same host/port/password you set in `config.ini`.

---

## Usage

### In-game chat commands

```
/fac <msg>          chat to the orchestrator (companionId 0)
/fac <id> <msg>     chat to a specific companion
/fac spawn [n]      request a spawn (optionally n companions)
/fac list           list companions
/fac kill [id]      kill companion(s)
```

Example: `/fac 1 mina hierro` → companion 1 mines iron.

### The reactive loop

One orchestrator manages every companion. Start it with:

```bash
bun run src/reactive-all.ts
```

It polls RCON for new `/fac` messages, hands them to Claude, and Claude responds with MCP tool
calls. A typical cycle:

1. Run the reactive loop (it blocks waiting for messages).
2. Parse incoming JSON: `[{companionId, player, message, tick}, ...]`.
3. Respond with MCP tools (e.g. `chat_say`, `resource_mine_until`).
4. Loop.

### Talking to the crew

```
User (in game): /fac 1 mina hierro

Companion 1:
  - chat_say(companionId: 1, message: "Voy a minar hierro")
  - resource_mine_until(companionId: 1, resource: "iron-ore", quantity: 50)
```

**Spawn companions** via MCP:
```
companion_spawn(companionId: 1)
companion_spawn(companionId: 2)
```

### Headless / fully autonomous

Companions spawn without a player (map-spawn fallback), so the whole crew can run over RCON on a
dedicated server with nobody connected — Claude can play *and* test itself.

```bash
bun run headless    # create the save if missing, then start the dedicated server (RCON on, auto_pause off)
bun run smoke       # live regression over RCON — exercises every command (PASS/FAIL/SKIP)

bun scripts/rcon.ts "fac_overview"                       # one-shot situational awareness
bun scripts/rcon.ts "fac_auto_factory 1 iron-gear-wheel" # turnkey factory
```

A human may optionally **Multiplayer → Connect** to `127.0.0.1` to spectate; the bot doesn't
depend on it.

> **Notes:** Factorio forbids `require()` at runtime (all requires happen at file load). Send plan
> JSON via single-quoted shell strings, and note that the first `/silent-command` right after a
> spawn is occasionally flaky — just retry.

---

## Tool reference

All tools live in `src/mcp/tools.ts` and are validated 1:1 against the Lua RCON commands.

| Family | Tools |
| --- | --- |
| **Chat** | `chat_get`, `chat_say` |
| **Companions** | `companion_spawn`, `companion_list`, `companion_status`, `companion_position`, `companion_inventory`, `companion_health`, `companion_disappear`, `companion_stop`, `companion_stop_all`, `set_specialty`, `attach_player`, `detach_player` |
| **Movement** | `move_to`, `move_follow`, `move_stop` |
| **Resources** | `resource_nearest`, `resource_list`, `resource_mine`, `resource_mine_status`, `resource_mine_stop`, `resource_mine_until` (skill) |
| **Items / crafting** | `item_pick`, `item_craft`, `item_craft_start`, `item_craft_status`, `item_craft_stop`, `item_recipes` |
| **Buildings** | `building_place`, `building_place_start`, `building_place_status`, `building_remove`, `building_can_place`, `building_info`, `building_rotate`, `building_recipe`, `building_fuel`, `building_fill`, `building_empty` |
| **Blueprints / belts** | `blueprint_place`, `blueprint_line`, `blueprint_status`, `blueprint_stop`, `belt_connect`, `belt_link` |
| **Logistics** | `haul`, `haul_status`, `haul_stop`, `refuel`, `refuel_status`, `refuel_stop` |
| **Combat** | `action_attack`, `action_attack_start`, `action_attack_status`, `action_attack_stop`, `action_defend`, `action_flee`, `action_patrol`, `action_nest_clear`, `action_repair`, `action_wololo`, `combat_until` (skill) |
| **Factory doctor (Pillar I)** | `factory_analyze`, `factory_graph`, `factory_fix`, `factory_wire`, `build_station`, `build_bank`, `auto_factory`, `production_plan`, `recipe_deps` |
| **Orchestration (Pillar II)** | `reserve`, `release`, `reservations`, `assign_role`, `assign_courier`, `clear_role`, `roles` |
| **Plans (Pillar II)** | `plan_create`, `plan_status`, `plan_step_done`, `plan_run` |
| **Memory (Pillar III)** | `memory_remember`, `memory_recall`, `memory_forget`, `memory_list`, `memory_goto`, `memory_nearest`, `survey_remember` |
| **Research** | `research_get`, `research_set`, `research_progress`, `tech_path` |
| **World / status** | `world_scan`, `world_nearest`, `world_enemies`, `world_survey`, `overview`, `session_status`, `context_clear`, `context_check`, `version`, `help` |

---

## Development

```bash
bun run check    # validate-tools (MCP↔Lua 1:1) + lint-lua-api (defines.* vs vendored API spec)
bun run smoke    # live regression suite (spawns + arms a throwaway test companion, builds for real)
bun run gen-api  # regenerate reference/factorio-api-slim.json from a runtime-api dump
```

A **lefthook** pre-commit hook runs `bun run check`. Useful one-offs:

```bash
bun scripts/rcon.ts "<fac_command>"   # send a raw RCON command
bun run scripts/validate-tools.ts     # 99 MCP tools must map to 100 RCON commands
```

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| **Connection refused** | Factorio isn't hosting multiplayer (RCON is off). Host a game. |
| **Unknown command `/fac`** | Mod not loaded — enable "AI Companion" in Mods and restart. |
| **3+ ECONNREFUSED in a row** | Factorio disconnected; stop the reactive loop and restart it. |
| **RCON auth fails** | `config.ini` socket/password don't match the MCP env vars. |
| **First action after spawn fails** | The first `/silent-command` post-spawn is occasionally flaky — retry. |

---

## Versioning

The mod version lives in [`factorio-mod/info.json`](factorio-mod/info.json); a grouped,
human-readable history is in [CHANGELOG.md](CHANGELOG.md).

---

## Credits & license

Inspired by the
[Factorio Learning Environment](https://github.com/JackHopkins/factorio-learning-environment).
See [LICENSE](LICENSE) for license terms.
