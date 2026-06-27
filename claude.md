# Factorio AI Companion

AI companions for Factorio 2.x via MCP tools + RCON.

## Quick Start

**Reactive loop (manages ALL companions):**

1. `Bash(run_in_background: true): bun run src/reactive-all.ts`
2. `TaskOutput(task_id, block: true, timeout: 120000)`
3. Parse JSON: `[{companionId, player, message, tick}, ...]`
4. Use MCP tools to respond/act
5. Loop

**Example:**
```
User: /fac 1 mina hierro

Your response:
- chat_say(companionId: 1, message: "Voy a minar hierro")
- resource_mine_until(companionId: 1, resource: "iron-ore", quantity: 50)
```

## MCP Tools (src/mcp/tools.ts)

**ALWAYS use MCP tools** (type-safe, validated 1:1 with Lua).

Categories:
- `chat_*` - say, get
- `companion_*` - spawn, list, status, stop, stop_all, position, inventory, health, disappear
- `move_*` - to, follow, stop
- `resource_*` - nearest, list, mine, mine_until (skill)
- `item_*` - pick, craft, recipes
- `building_*` - place, remove, info, rotate, fuel, fill, empty
- `blueprint_*` - place, line, status, stop (mass construction)
- `haul`/`refuel` - logistics queues
- `action_*` / combat - attack, defend, flee, patrol, wololo, nest_clear, repair, combat_until (skill)
- `research_*` - get, set, progress; `tech_path` (prereq chain)
- `world_*` - scan, nearest, survey
- **factory doctor (Pillar I)** - `factory_analyze` (bottlenecks + dead-machine issues), `factory_graph`, `factory_fix` (place+power+fuel), `production_plan`, `recipe_deps`
- **orchestration** - `reserve`/`release`/`reservations`, `assign_role`/`clear_role`/`roles`
- **plans (self-driving, Pillar II)** - `plan_create` (auto + DAG `deps` → parallel crew), `plan_status`, `plan_step_done`, `plan_run` on|off
- **memory (Pillar III)** - `memory_remember`/`recall`/`forget`/`list`/`goto` (named locations show as map tags)
- `context_*` - clear, check

**Spawn companions:**
```
companion_spawn(companionId: 1)
companion_spawn(companionId: 2)
```

**Key principle:** ONE orchestrator manages ALL companions (id=0,1,2,...). NO separate Task subagents.

## Player Commands (in-game)

```
/fac <msg>         -- Chat to orchestrator (companionId=0)
/fac <id> <msg>    -- Chat to companion
/fac spawn [n]     -- Request spawn
/fac list          -- List companions
/fac kill [id]     -- Kill companion(s)
```

## Setup

**Factorio config** (`%APPDATA%\Factorio\config\config.ini`):
```ini
local-rcon-socket=127.0.0.1:34198
local-rcon-password=factorio
```
(Should be in the file, not under a specific section)

**Run:** Multiplayer → Host New Game (RCON only works in multiplayer)

**Install mod:** Copy `factorio-mod/` → `%APPDATA%\Factorio\mods\ai-companion\`

**Update mod:**
```bash
# Windows command (use this, xcopy has path issues in bash)
cp -r /c/Users/lveil/Desktop/Projects/factorio-ai-companion/factorio-mod/* /c/Users/lveil/AppData/Roaming/Factorio/mods/ai-companion/
```
Restart Factorio.

## Troubleshooting

- **Connection refused:** Factorio not running in multiplayer mode
- **Unknown command:** Mod not loaded, restart Factorio
- **3+ ECONNREFUSED:** Factorio disconnected, kill reactive-all task and restart

## References

- FLE (inspiration): `../factorio-learning-environment/`
- Validation: `bun run scripts/validate-tools.ts` (54 tools = 54 Lua commands)
- Lefthook runs validation on pre-commit
