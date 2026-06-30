import { z } from "zod";

export const SendMessageSchema = z.object({
  message: z.string(),
});

// Single source of truth for all MCP tools
// Format: toolName -> { desc, rcon (template), params }
export const TOOLS: Record<string, {
  desc: string;
  rcon: string;  // Template with {param} placeholders
  params: Record<string, { type: "number" | "string"; desc?: string; required?: boolean; default?: any }>;
}> = {
  // Chat
  chat_get: {
    desc: "Get unread messages from Factorio chat",
    rcon: "/fac_chat_get {companionId}",
    params: { companionId: { type: "number", desc: "Optional: filter by companion ID" } }
  },
  chat_say: {
    desc: "Send a message to Factorio chat as a companion",
    rcon: "/fac_chat_say {companionId} {message}",
    params: {
      companionId: { type: "number", desc: "Companion ID (0 for orchestrator)", required: true },
      message: { type: "string", desc: "Message to send", required: true }
    }
  },

  // Companion
  companion_list: {
    desc: "List ALL companions with positions and health",
    rcon: "/fac_companion_list",
    params: {}
  },
  companion_spawn: {
    desc: "Spawn a new companion character",
    rcon: "/fac_companion_spawn id={companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  companion_position: {
    desc: "Get companion position and nearby entities",
    rcon: "/fac_companion_position {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  companion_inventory: {
    desc: "Get companion inventory contents",
    rcon: "/fac_companion_inventory {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  companion_health: {
    desc: "Get companion health status",
    rcon: "/fac_companion_health {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  companion_disappear: {
    desc: "Despawn a companion (drops items). A player attachment is just detached, never destroyed.",
    rcon: "/fac_companion_disappear {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  attach_player: {
    desc: "Attach the autopilot to a real player's OWN character under this id, so every companion skill/plan can drive the protagonist (move/mine/build/combat/plans). The player's live input still wins per tick — this drives them when they're AFK, and fully when no human is at the keyboard. Never owns/destroys the character.",
    rcon: "/fac_attach_player {companionId} {playerName}",
    params: {
      companionId: { type: "number", desc: "id to register the player character under", required: true },
      playerName: { type: "string", desc: "Player to attach (default: first player)", default: "" }
    }
  },
  detach_player: {
    desc: "Release the autopilot from a player's character (does not destroy the character).",
    rcon: "/fac_detach_player {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  companion_stop_all: {
    desc: "Stop all queues for a companion (harvest, craft, build, combat, walk)",
    rcon: "/fac_companion_stop_all {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  set_specialty: {
    desc: "Crew specialization (Pillar II): tag a companion's specialty so the plan executor's auto-allocation prefers it for matching jobs — miner→mine, builder→build_line/craft, hauler→haul (fighter reserved; any=clear). Among matching specialists it still picks the nearest. Emergent division of labor.",
    rcon: "/fac_set_specialty {companionId} {specialty}",
    params: {
      companionId: { type: "number", required: true },
      specialty: { type: "string", desc: "miner | builder | hauler | fighter | any", required: true }
    }
  },

  // Movement
  move_to: {
    desc: "Move companion to specific coordinates",
    rcon: "/fac_move_to {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  move_follow: {
    desc: "Make companion follow a player",
    rcon: "/fac_move_follow {companionId} {playerName}",
    params: {
      companionId: { type: "number", required: true },
      playerName: { type: "string", desc: "Player name to follow", required: true }
    }
  },
  move_stop: {
    desc: "Stop companion movement",
    rcon: "/fac_move_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },

  // Resources
  resource_nearest: {
    desc: "Find nearest resource of a type",
    rcon: "/fac_resource_nearest {companionId} {resourceType}",
    params: {
      companionId: { type: "number", required: true },
      resourceType: { type: "string", desc: "Resource: iron-ore, copper-ore, coal, stone", required: true }
    }
  },
  resource_list: {
    desc: "List nearby resources around companion",
    rcon: "/fac_resource_list {companionId} {filter} {radius}",
    params: {
      companionId: { type: "number", required: true },
      filter: { type: "string", desc: "Optional: filter by resource type", default: "" },
      radius: { type: "number", desc: "Search radius", default: 50 }
    }
  },
  resource_mine: {
    desc: "Start mining at coordinates (companion must be within 5 tiles)",
    rcon: "/fac_resource_mine {companionId} {x} {y} {count} {resourceName}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      count: { type: "number", desc: "Number to mine", default: 1 },
      resourceName: { type: "string", desc: "Optional: specific resource", default: "" }
    }
  },
  resource_mine_status: {
    desc: "Check mining queue status",
    rcon: "/fac_resource_mine_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  resource_mine_stop: {
    desc: "Stop mining queue (v0.11.0+: uses hybrid native mining)",
    rcon: "/fac_resource_mine_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  // NOTE: mine_real_* removed in v0.11.0 - resource_mine now uses hybrid native mining

  // Items
  item_pick: {
    desc: "Pick up items from ground near companion",
    rcon: "/fac_item_pick {companionId} {itemName} {radius}",
    params: {
      companionId: { type: "number", required: true },
      itemName: { type: "string", required: true },
      radius: { type: "number", default: 10 }
    }
  },
  item_craft: {
    desc: "Craft an item (instant)",
    rcon: "/fac_item_craft {companionId} {recipe} {count}",
    params: {
      companionId: { type: "number", required: true },
      recipe: { type: "string", required: true },
      count: { type: "number", default: 1 }
    }
  },
  item_craft_start: {
    desc: "Start crafting (async, tick-based)",
    rcon: "/fac_item_craft_start {companionId} {recipe} {count}",
    params: {
      companionId: { type: "number", required: true },
      recipe: { type: "string", required: true },
      count: { type: "number", default: 1 }
    }
  },
  item_craft_status: {
    desc: "Check crafting status",
    rcon: "/fac_item_craft_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  item_craft_stop: {
    desc: "Stop crafting",
    rcon: "/fac_item_craft_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  item_recipes: {
    desc: "List available recipes for companion",
    rcon: "/fac_item_recipes {companionId}",
    params: { companionId: { type: "number", required: true } }
  },

  // World
  world_scan: {
    desc: "Scan for entities around companion",
    rcon: "/fac_world_scan {companionId} {radius} {entityType}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", default: 50 },
      entityType: { type: "string", default: "" }
    }
  },
  world_nearest: {
    desc: "Find nearest entity of a type",
    rcon: "/fac_world_nearest {companionId} {entityName}",
    params: {
      companionId: { type: "number", required: true },
      entityName: { type: "string", required: true }
    }
  },
  world_enemies: {
    desc: "Find enemies around companion",
    rcon: "/fac_world_enemies {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", default: 50 }
    }
  },

  // Building
  building_place: {
    desc: "Place a building/entity at coordinates (instant)",
    rcon: "/fac_building_place {companionId} {entityName} {x} {y} {direction}",
    params: {
      companionId: { type: "number", required: true },
      entityName: { type: "string", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      direction: { type: "number", desc: "Direction 0-7", default: 0 }
    }
  },
  building_place_start: {
    desc: "Start placing a building (async, tick-based)",
    rcon: "/fac_building_place_start {companionId} {entityName} {x} {y} {direction}",
    params: {
      companionId: { type: "number", required: true },
      entityName: { type: "string", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      direction: { type: "number", default: 0 }
    }
  },
  building_place_status: {
    desc: "Check building placement status",
    rcon: "/fac_building_place_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  building_remove: {
    desc: "Remove a building at coordinates",
    rcon: "/fac_building_remove {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  building_can_place: {
    desc: "Check if entity can be placed at coordinates",
    rcon: "/fac_building_can_place {companionId} {entityName} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      entityName: { type: "string", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  building_info: {
    desc: "Get building info at coordinates",
    rcon: "/fac_building_info {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  building_rotate: {
    desc: "Rotate a building at coordinates",
    rcon: "/fac_building_rotate {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  building_recipe: {
    desc: "Get/set recipe for assembling machine",
    rcon: "/fac_building_recipe {companionId} {x} {y} {recipe}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      recipe: { type: "string", default: "" }
    }
  },
  building_fuel: {
    desc: "Add fuel to entity (burner, furnace, etc)",
    rcon: "/fac_building_fuel {companionId} {x} {y} {fuelName} {count}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      fuelName: { type: "string", required: true },
      count: { type: "number", required: true }
    }
  },
  building_empty: {
    desc: "Empty contents from entity",
    rcon: "/fac_building_empty {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  building_fill: {
    desc: "Fill entity with items",
    rcon: "/fac_building_fill {companionId} {x} {y} {itemName} {count}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      itemName: { type: "string", required: true },
      count: { type: "number", required: true }
    }
  },

  // Blueprint / mass construction (Phase 2): stamp ghosts, then build them fairly
  // (companion walks via pathfinding, consumes inventory, revives each ghost).
  blueprint_place: {
    desc: "Place a blueprint (as ghosts) from an export string at coords, then auto-build it ghost-by-ghost. Reports materials needed/short.",
    rcon: "/fac_blueprint_place {companionId} {x} {y} {blueprint}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", desc: "Anchor X", required: true },
      y: { type: "number", desc: "Anchor Y", required: true },
      blueprint: { type: "string", desc: "Blueprint export string", required: true }
    }
  },
  blueprint_line: {
    desc: "Stamp a straight line of N entity ghosts and build them (belts/inserters/poles). direction: 0=N,1=E,2=S,3=W.",
    rcon: "/fac_blueprint_line {companionId} {entityName} {x} {y} {direction} {count}",
    params: {
      companionId: { type: "number", required: true },
      entityName: { type: "string", desc: "Entity to place, e.g. transport-belt", required: true },
      x: { type: "number", desc: "Start X", required: true },
      y: { type: "number", desc: "Start Y", required: true },
      direction: { type: "number", desc: "0=N,1=E,2=S,3=W", default: 1 },
      count: { type: "number", desc: "Number of entities", default: 5 }
    }
  },
  blueprint_status: {
    desc: "Check blueprint/line build progress (built, remaining, blocked, missing materials)",
    rcon: "/fac_blueprint_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  blueprint_stop: {
    desc: "Stop the current blueprint build (leaves remaining ghosts in the world)",
    rcon: "/fac_blueprint_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },

  // Logistics (Phase 3): fair-play hauling + refueling (companion walks via pathfinding,
  // carries items in its own inventory, takes/gives one entity at a time).
  haul: {
    desc: "Haul an item from a source position to a dest position, looping. quota<=0 means endless until source empties.",
    rcon: "/fac_haul {companionId} {item} {sx} {sy} {dx} {dy} {quota}",
    params: {
      companionId: { type: "number", required: true },
      item: { type: "string", desc: "Item to move, e.g. iron-ore", required: true },
      sx: { type: "number", desc: "Source X", required: true },
      sy: { type: "number", desc: "Source Y", required: true },
      dx: { type: "number", desc: "Dest X", required: true },
      dy: { type: "number", desc: "Dest Y", required: true },
      quota: { type: "number", desc: "Total to deliver (<=0 = endless)", default: 0 }
    }
  },
  haul_status: {
    desc: "Check haul progress (item, delivered, quota, phase)",
    rcon: "/fac_haul_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  haul_stop: {
    desc: "Stop hauling",
    rcon: "/fac_haul_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  refuel: {
    desc: "Keep burners within radius of a point topped up with fuel from the companion's inventory (endless until out of fuel).",
    rcon: "/fac_refuel {companionId} {fuel} {x} {y} {radius}",
    params: {
      companionId: { type: "number", required: true },
      fuel: { type: "string", desc: "Fuel item, e.g. coal", required: true },
      x: { type: "number", desc: "Area center X", required: true },
      y: { type: "number", desc: "Area center Y", required: true },
      radius: { type: "number", desc: "Area radius", default: 20 }
    }
  },
  refuel_status: {
    desc: "Check refuel status (fuel, units refueled)",
    rcon: "/fac_refuel_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  refuel_stop: {
    desc: "Stop refueling",
    rcon: "/fac_refuel_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },

  // Action/Combat
  action_attack: {
    desc: "Attack an entity at coordinates (instant)",
    rcon: "/fac_action_attack {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  action_attack_start: {
    desc: "Start attacking (async, tick-based combat)",
    rcon: "/fac_action_attack_start {companionId} {x} {y}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true }
    }
  },
  action_attack_status: {
    desc: "Check attack status",
    rcon: "/fac_action_attack_status {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  action_attack_stop: {
    desc: "Stop attacking",
    rcon: "/fac_action_attack_stop {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  action_defend: {
    desc: "Defend current position (attack nearby enemies)",
    rcon: "/fac_action_defend {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", default: 20 }
    }
  },
  action_flee: {
    desc: "Flee from danger",
    rcon: "/fac_action_flee {companionId} {x} {y} {distance}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      distance: { type: "number", required: true }
    }
  },
  action_patrol: {
    desc: "Patrol a route of waypoints (JSON array of {x,y}), engaging enemies that come within range, then resuming the route. Stop with companion_stop_all or move_stop.",
    rcon: "/fac_action_patrol {companionId} {points}",
    params: {
      companionId: { type: "number", required: true },
      points: { type: "string", desc: "JSON array of {x,y} points", required: true }
    }
  },
  action_nest_clear: {
    desc: "Clear a nest area (Phase 4b): advance and shoot spawners/worms/biters in range, retreat when HP drops or ammo runs dry, recover (natural regen + own ammo), then re-engage. Out of ammo -> stops and reports. Fair-play: own resources only. Stop with companion_stop_all/move_stop.",
    rcon: "/fac_action_nest_clear {companionId} {x} {y} {radius}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", desc: "Nest center X", required: true },
      y: { type: "number", desc: "Nest center Y", required: true },
      radius: { type: "number", desc: "Scan radius for targets", default: 32 }
    }
  },
  action_repair: {
    desc: "Maintain an area (Phase 4c): repair-pack damaged friendly structures and refill ammo-turrets from the companion's own inventory. Endless until supplies run out. Stop with companion_stop_all/move_stop.",
    rcon: "/fac_action_repair {companionId} {x} {y} {radius} {ammo}",
    params: {
      companionId: { type: "number", required: true },
      x: { type: "number", desc: "Area center X", required: true },
      y: { type: "number", desc: "Area center Y", required: true },
      radius: { type: "number", desc: "Maintenance radius", default: 24 },
      ammo: { type: "string", desc: "Optional turret ammo item to refill, e.g. firearm-magazine", default: "" }
    }
  },
  action_wololo: {
    desc: "Play wololo sound",
    rcon: "/fac_action_wololo {companionId}",
    params: { companionId: { type: "number", required: true } }
  },

  // Orchestration (Phase 5a: task-board / reservations)
  reserve: {
    desc: "Claim a target so other companions skip it (key 'e:<unit_number>' for an entity or 'p:<x>,<y>' for a position/area). Mostly automatic inside mining/build/nest skills; exposed for manual or LLM-side coordination.",
    rcon: "/fac_reserve {companionId} {key}",
    params: {
      companionId: { type: "number", required: true },
      key: { type: "string", desc: "Reservation key, e.g. p:10,20 or e:1234", required: true }
    }
  },
  release: {
    desc: "Release a reservation this companion holds.",
    rcon: "/fac_release {companionId} {key}",
    params: {
      companionId: { type: "number", required: true },
      key: { type: "string", required: true }
    }
  },
  reservations: {
    desc: "List all active reservations (key -> companion id).",
    rcon: "/fac_reservations",
    params: {}
  },

  // Standing roles (Phase 5c: auto-response)
  assign_role: {
    desc: "Assign a standing role over an area (auto-triggers a skill when warranted): guard (nest_clear when enemies enter), refueler (refuel low burners; item=fuel), maintainer (repair/refill; item=turret ammo). Companion must carry its own supplies. Persists across saves.",
    rcon: "/fac_assign_role {companionId} {role} {x} {y} {radius} {item}",
    params: {
      companionId: { type: "number", required: true },
      role: { type: "string", desc: "guard | refueler | maintainer", required: true },
      x: { type: "number", required: true },
      y: { type: "number", required: true },
      radius: { type: "number", default: 24 },
      item: { type: "string", desc: "fuel item (refueler) or turret ammo (maintainer)", default: "" }
    }
  },
  assign_courier: {
    desc: "Assign a CONTINUOUS courier role: the companion ferries `item` from a source position to a dest position whenever the source has it (re-triggers like refueler) — a self-sustaining supply line between two stations (e.g. a furnace's output_chest → an assembler's input_chest from auto_factory's flow map). Persists across saves; clear with clear_role.",
    rcon: "/fac_assign_courier {companionId} {item} {sx} {sy} {dx} {dy} {batch}",
    params: {
      companionId: { type: "number", required: true },
      item: { type: "string", desc: "Item to ferry", required: true },
      sx: { type: "number", desc: "source x", required: true },
      sy: { type: "number", desc: "source y", required: true },
      dx: { type: "number", desc: "dest x", required: true },
      dy: { type: "number", desc: "dest y", required: true },
      batch: { type: "number", desc: "items per trip", default: 50 }
    }
  },
  clear_role: {
    desc: "Clear a companion's standing role (guard/refueler/maintainer/courier).",
    rcon: "/fac_clear_role {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  roles: {
    desc: "List all standing roles.",
    rcon: "/fac_roles",
    params: {}
  },

  // Planning queries + task tree (Phase 5b)
  world_survey: {
    desc: "Survey an area: resource patches by type (count + amount) and friendly buildings by type. Planning input for goal decomposition.",
    rcon: "/fac_world_survey {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", default: 100 }
    }
  },
  recipe_deps: {
    desc: "Recipe dependency tree: ingredients a recipe needs, recursively to depth.",
    rcon: "/fac_recipe_deps {recipe} {depth}",
    params: {
      recipe: { type: "string", desc: "Recipe name, e.g. electronic-circuit", required: true },
      depth: { type: "number", default: 2 }
    }
  },
  factory_analyze: {
    desc: "Factory doctor DIAGNOSE: scan crafting machines + drills in radius, compute each item's production vs consumption rate (items/sec from live crafting_speed), flag bottlenecks (consumed faster than produced), AND list dead machines by reason in `issues` (unpowered / idle no-recipe / no-fuel). Answers \"what's bottlenecked\" and \"why is this machine dead\".",
    rcon: "/fac_factory_analyze {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", desc: "Scan radius", default: 50 }
    }
  },
  factory_graph: {
    desc: "Production graph: recipe-level DAG of an area — for each item, which recipes produce it and which consume it (and how many machines).",
    rcon: "/fac_factory_graph {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", default: 50 }
    }
  },
  factory_fix: {
    desc: "Factory doctor TREAT: find the worst fixable bottleneck and, if the companion carries the right machine, place it + set its recipe + ENERGIZE it (drop a connected pole line to the nearest grid for electric machines, or fuel a burner) near the companion. Reports the recipe's needs_inputs so a plan/haul can feed it. Still manual: belt/inserter routing of inputs.",
    rcon: "/fac_factory_fix {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", default: 50 }
    }
  },
  factory_wire: {
    desc: "Factory doctor WIRE (Pillar I): turn the nearest assembling-machine (with a recipe) into a self-feeding station — input inserters pulling from buffer chests into the machine + an output inserter into an output chest, all from the companion's inventory. Then a haul plan keeps the input chests stocked (supply-chain handoff). Pair with factory_fix (which places+powers the machine).",
    rcon: "/fac_factory_wire {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", desc: "Search radius for the machine", default: 16 }
    }
  },
  build_station: {
    desc: "Pillar I capstone — build a COMPLETE working station for a recipe in one shot: place the right machine near the companion (assembler, or furnace for smelting) + set recipe + energize (drop a pole line to grid / fuel a burner) + wire I/O inserters & buffer chests. Returns io.input_chest so you can immediately haul ingredients to it (products collect in io.output_chest). Needs the machine + inserters + chests (+ poles/fuel) in inventory. Chain per production_plan step to build a whole factory.",
    rcon: "/fac_build_station {companionId} {recipe}",
    params: {
      companionId: { type: "number", required: true },
      recipe: { type: "string", desc: "Recipe to build a station for, e.g. iron-gear-wheel", required: true }
    }
  },
  auto_factory: {
    desc: "Pillar I APEX — 'build me a factory for X' in one command. Walks the recipe DAG and builds a COMPLETE station (place+power/fuel+wire) for the target and EVERY intermediate, then (connect=1, default) auto-assigns a free companion as a continuous COURIER for each material-flow edge so the factory runs hands-off. Returns stations, flow map, couriers assigned, any `unconnected` edges (spawn more companions for those), and raw_inputs. Just supply raws to the leaf input chests. Needs enough machines/inserters/chests/poles(+fuel) in the builder's inventory + a power grid nearby + one free companion per flow edge.",
    rcon: "/fac_auto_factory {companionId} {item} {rate} {connect}",
    params: {
      companionId: { type: "number", desc: "Builder companion", required: true },
      item: { type: "string", desc: "Target item, e.g. electronic-circuit", required: true },
      rate: { type: "number", desc: "Target items/sec (informational)", default: 1 },
      connect: { type: "number", desc: "1 = auto-assign couriers (default), 0 = just build + report flow", default: 1 }
    }
  },
  production_plan: {
    desc: "Production planner (Pillar I): given a target item + rate/sec, recurse the recipe DAG to compute rate + baseline machine count for every intermediate and the raw inputs needed. The ratio math behind \"build me X/s of Y\".",
    rcon: "/fac_production_plan {companionId} {item} {rate}",
    params: {
      companionId: { type: "number", required: true },
      item: { type: "string", desc: "Target item, e.g. electronic-circuit", required: true },
      rate: { type: "number", desc: "Target items/sec", default: 1 }
    }
  },
  plan_create: {
    desc: "Create a persistent task plan (survives saves). Param is JSON {goal, auto?, steps[]}. A step is plain text (manual; advance with plan_step_done) OR {desc, action} where action is auto-executed by the colony when auto=true (or after plan_run). Action types: " +
      "{type:'mine', target:{x,y}, resource:'iron-ore', qty:50} — walk to patch + mine; " +
      "{type:'craft', recipe:'iron-gear-wheel', qty:20}; " +
      "{type:'build_line', entity:'transport-belt', x, y, dir:0..3, count:10} (single machine = count 1, builds via ghosts the companion walks to); " +
      "{type:'haul', item:'iron-ore', source:{x,y}, dest:{x,y}, quota:200}; " +
      "{type:'research', tech:'automation'} (force-level, no companion). Add action.cid to pin a step to a specific companion. " +
      "PARALLELISM: each step may declare deps:[stepIndices] (1-based) and runs as soon as those finish — independent steps run AT THE SAME TIME across the crew, each claimed by the nearest free companion (emergent division of labor). Omit deps for the default sequential chain (each step waits on the previous); deps:[] starts immediately. This expresses supply chains: e.g. step1 mine ore, step2 (deps:[1]) haul ore to smelter, step3 (deps:[2]) craft.",
    rcon: "/fac_plan_create {plan}",
    params: {
      plan: { type: "string", desc: "JSON {goal, auto?, steps[]} — see desc for action schema", required: true }
    }
  },
  plan_status: {
    desc: "Get a plan's progress (with per-step status/action/assigned companion), or list all plans if planId omitted/0.",
    rcon: "/fac_plan_status {planId}",
    params: {
      planId: { type: "number", desc: "Plan id; 0 lists all", default: 0 }
    }
  },
  plan_step_done: {
    desc: "Manually mark the plan's current step done and advance (for text/manual steps).",
    rcon: "/fac_plan_step_done {planId}",
    params: { planId: { type: "number", required: true } }
  },
  plan_run: {
    desc: "Toggle a plan's auto-execution. on = the colony self-drives the active step (claim free companion, reserve, build/mine/craft/haul/research, advance). off = pause + halt the in-flight step.",
    rcon: "/fac_plan_run {planId} {state}",
    params: {
      planId: { type: "number", required: true },
      state: { type: "string", desc: "on|off (default on)", default: "on" }
    }
  },

  // Memory (Pillar III: a buddy who knows you) — persistent, save-surviving knowledge.
  memory_remember: {
    desc: "Remember something durable about the player/world (survives saves). JSON: " +
      "{type:'location', name:'iron mine', kind?:'ore|base|defense|custom', x?, y?, companionId?, note?} (give x/y, or a companionId to capture that companion's current position = 'remember here as X'); " +
      "{type:'pref', key:'belts', value:'red'} (playstyle/layout preference); " +
      "{type:'note', text:'...', x?, y?}.",
    rcon: "/fac_memory_remember {memory}",
    params: { memory: { type: "string", desc: "JSON memory entry — see desc", required: true } }
  },
  memory_recall: {
    desc: "Recall remembered knowledge. type = location|pref|note|all; optional substring filters name/kind/key/value/text. Call at session start to know the player's places & preferences.",
    rcon: "/fac_memory_recall {type} {query}",
    params: {
      type: { type: "string", desc: "location|pref|note|all", default: "all" },
      query: { type: "string", desc: "Optional substring filter", default: "" }
    }
  },
  memory_forget: {
    desc: "Forget a remembered entry. type = location|pref|note; key = the name/key, or the 1-based index for a note.",
    rcon: "/fac_memory_forget {type} {key}",
    params: {
      type: { type: "string", desc: "location|pref|note", required: true },
      key: { type: "string", desc: "name/key, or note index", required: true }
    }
  },
  memory_list: {
    desc: "Dump all remembered locations, preferences, and notes (with counts).",
    rcon: "/fac_memory_list",
    params: {}
  },
  memory_goto: {
    desc: "Walk a companion to a remembered named location (e.g. 'iron mine').",
    rcon: "/fac_memory_goto {companionId} {name}",
    params: {
      companionId: { type: "number", required: true },
      name: { type: "string", desc: "Remembered location name", required: true }
    }
  },
  survey_remember: {
    desc: "Pillar III — the buddy learns the map: scan resource patches around the companion and auto-remember ONE location per resource type at its centroid (kind='ore', shown as a map tag). Builds up persistent knowledge of where the ores are. Recall later with memory_nearest/recall/goto.",
    rcon: "/fac_survey_remember {companionId} {radius}",
    params: {
      companionId: { type: "number", required: true },
      radius: { type: "number", desc: "Scan radius", default: 100 }
    }
  },
  memory_nearest: {
    desc: "Recall the NEAREST remembered location to the companion, optionally filtered by kind/name substring (e.g. 'ore', 'iron'). The buddy using what it knows — pair with memory_goto.",
    rcon: "/fac_memory_nearest {companionId} {query}",
    params: {
      companionId: { type: "number", required: true },
      query: { type: "string", desc: "Optional kind/name filter (e.g. ore, iron, base)", default: "" }
    }
  },

  // Research
  research_get: {
    desc: "Get current research status",
    rcon: "/fac_research_get {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  research_set: {
    desc: "Set research target",
    rcon: "/fac_research_set {companionId} {technology}",
    params: {
      companionId: { type: "number", required: true },
      technology: { type: "string", required: true }
    }
  },
  research_progress: {
    desc: "Get research progress",
    rcon: "/fac_research_progress {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  tech_path: {
    desc: "Tech planning: unresearched prerequisite chain for a target technology, in topological order (what to research, in what order).",
    rcon: "/fac_tech_path {companionId} {technology}",
    params: {
      companionId: { type: "number", required: true },
      technology: { type: "string", required: true }
    }
  },

  // Context
  context_clear: {
    desc: "Clear companion context (for thread management)",
    rcon: "/fac_context_clear {companionId}",
    params: { companionId: { type: "number", required: true } }
  },
  context_check: {
    desc: "Check pending context clear requests",
    rcon: "/fac_context_check",
    params: {}
  },

  // Meta
  overview: {
    desc: "One-shot situational awareness: companions (count/ids), running plans (goal/progress/auto), standing roles, live reservation count, and memory counts (locations/prefs/notes). Call at session start to see everything going on.",
    rcon: "/fac_overview",
    params: {}
  },
  version: {
    desc: "Get mod version",
    rcon: "/fac_version",
    params: {}
  },
  help: {
    desc: "Get help and list of commands",
    rcon: "/fac_help {category}",
    params: {
      category: { type: "string", desc: "Optional: category to filter (action, building, etc)", default: "" }
    }
  },
};

// High-level skills (run as background processes, not direct RCON)
export const SKILLS: Record<string, {
  desc: string;
  script: string;  // Script path relative to src/
  params: Record<string, { type: "number" | "string"; desc?: string; required?: boolean; default?: any }>;
}> = {
  resource_mine_until: {
    desc: "HIGH-LEVEL: Autonomously mine resource until target amount. Handles walking, mining, repeat. Runs in background.",
    script: "skills/mine-until.ts",
    params: {
      companionId: { type: "number", required: true },
      resource: { type: "string", desc: "Resource: iron, copper, coal, stone, uranium", required: true },
      amount: { type: "number", desc: "Target amount", default: 50 }
    }
  },
  combat_until: {
    desc: "HIGH-LEVEL: Autonomously hunt and kill enemies. Handles scanning, walking, attacking. Runs in background.",
    script: "skills/combat-until.ts",
    params: {
      companionId: { type: "number", required: true },
      targetType: { type: "string", desc: "Target: all, spawner, worm, biter, spitter", default: "all" },
      maxKills: { type: "number", desc: "Max kills before stopping", default: 10 }
    }
  },
};

// Special tools that need TS-side handling (not just RCON passthrough)
const SPECIAL_TOOLS = [
  {
    name: "session_status",
    description: "Get current session state and instructions. Call this FIRST to understand what's running and how to start the reactive loop.",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: []
    }
  },
  {
    name: "companion_status",
    description: "Get unified status of ONE companion: current state/task (idle, mining, crafting, building, combat, walking, following), position, health, top inventory items, plus any running background skill.",
    inputSchema: {
      type: "object" as const,
      properties: {
        companionId: { type: "number", description: "Companion ID to check" }
      },
      required: ["companionId"]
    }
  },
  {
    name: "companion_stop",
    description: "Stop a running skill for ONE companion (kills the background process).",
    inputSchema: {
      type: "object" as const,
      properties: {
        companionId: { type: "number", description: "Companion whose skill to stop" }
      },
      required: ["companionId"]
    }
  }
];

// Generate skill schemas (includes SKILLS + skill management tools)
export function generateSkillSchemas() {
  const skillSchemas = Object.entries(SKILLS).map(([name, skill]) => ({
    name,
    description: skill.desc,
    inputSchema: {
      type: "object" as const,
      properties: Object.fromEntries(
        Object.entries(skill.params).map(([pName, p]) => [
          pName,
          { type: p.type, description: p.desc }
        ])
      ),
      required: Object.entries(skill.params)
        .filter(([_, p]) => p.required)
        .map(([name]) => name)
    }
  }));

  return [...skillSchemas, ...SPECIAL_TOOLS];
}

// Generate MCP tool schemas from TOOLS
export function generateToolSchemas() {
  return Object.entries(TOOLS).map(([name, tool]) => ({
    name,
    description: tool.desc,
    inputSchema: {
      type: "object" as const,
      properties: Object.fromEntries(
        Object.entries(tool.params).map(([pName, p]) => [
          pName,
          { type: p.type, description: p.desc }
        ])
      ),
      required: Object.entries(tool.params)
        .filter(([_, p]) => p.required)
        .map(([name]) => name)
    }
  }));
}

// Build RCON command from template and args
export function buildRCONCommand(toolName: string, args: Record<string, any>): string {
  const tool = TOOLS[toolName];
  if (!tool) return ""; // Return empty for unknown tools (handled separately)

  let cmd = tool.rcon;

  // Replace placeholders with args or defaults
  for (const [param, config] of Object.entries(tool.params)) {
    const value = args[param] ?? config.default ?? "";
    cmd = cmd.replace(`{${param}}`, String(value));
  }

  // Clean up extra spaces
  return cmd.replace(/\s+/g, " ").trim();
}
