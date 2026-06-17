-- AI Companion v0.9.0 - Tick-based queue system
local u = require("commands.init")
local nav = require("commands.navigation")

local M = {}

-- Constants
local TICK_INTERVAL = 5
local MIN_ACTION_TICKS = 30
local BUILD_TICKS = 60
local ATTACK_COOLDOWN = 15
local ATTACK_RANGE = 6
local MINING_RANGE = 5

-- Validate companion exists and is valid
local function valid_companion(id)
  local c = u.get_companion(id)
  return c and c.entity and c.entity.valid and c
end

-- Generic queue processor - eliminates repetition across all tick functions
local function process_queue(queue_name, processor)
  local queues = storage[queue_name]
  if not queues then return end

  local to_remove = {}
  for cid, q in pairs(queues) do
    local c = valid_companion(cid)
    if not c then
      to_remove[#to_remove + 1] = cid
    else
      local should_remove = processor(cid, q, c)
      if should_remove then to_remove[#to_remove + 1] = cid end
    end
  end

  for _, cid in ipairs(to_remove) do queues[cid] = nil end
end

function M.init()
  storage.harvest_queues = storage.harvest_queues or {}
  storage.craft_queues = storage.craft_queues or {}
  storage.build_queues = storage.build_queues or {}
  storage.combat_queues = storage.combat_queues or {}
  storage.ghost_build_queues = storage.ghost_build_queues or {}
  storage.haul_queues = storage.haul_queues or {}
  storage.refuel_queues = storage.refuel_queues or {}
  storage.logistics_last = storage.logistics_last or {}
end

-- ============ HARVEST ============

function M.start_harvest(cid, position, target_count, resource_name)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  -- Filter by resource name if specified, otherwise get all resources
  local filter = {position = position, radius = 3, type = "resource"}
  if resource_name then filter.name = resource_name end

  local entities = c.entity.surface.find_entities_filtered(filter)
  if #entities == 0 then return {error = "No resource"} end

  table.sort(entities, function(a, b)
    return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position)
  end)

  storage.harvest_queues[cid] = {
    entities = entities,
    position = position,
    target = target_count,
    harvested = 0,
    current = nil,
    resource_name = resource_name
  }

  M.start_mining_next(cid)
  -- Set inv_snapshot immediately after starting mining
  storage.harvest_queues[cid].inv_snapshot = c.entity.get_main_inventory().get_contents()
  return {started = true, entities = #entities, target = target_count, resource = resource_name}
end

function M.start_mining_next(cid)
  local q = storage.harvest_queues[cid]
  if not q then return false end

  local c = valid_companion(cid)
  if not c then
    storage.harvest_queues[cid] = nil
    return false
  end

  while #q.entities > 0 do
    local entity = table.remove(q.entities, 1)
    if entity and entity.valid then
      c.entity.update_selected_entity(entity.position)
      c.entity.mining_state = {mining = true, position = entity.position}
      q.current = {
        entity = entity,
        start_tick = game.tick,
        mining_time = (entity.prototype.mineable_properties.mining_time or 1) * 60
      }
      return true
    end
  end
  return false
end

function M.tick_harvest_queues()
  process_queue("harvest_queues", function(cid, q, c)
    -- Target reached
    if q.harvested >= q.target then
      c.entity.mining_state = {mining = false}
      return true
    end

    -- Too far from mining area
    if u.distance(c.entity.position, q.position) > MINING_RANGE then
      c.entity.mining_state = {mining = false}
      return true
    end

    -- Start mining first resource
    if not q.current then
      if not M.start_mining_next(cid) then
        c.entity.mining_state = {mining = false}
        return true
      end
      q.inv_snapshot = c.entity.get_main_inventory().get_contents()
      return false
    end

    local current = q.current

    -- HYBRID: Let Factorio mine natively, monitor mining_state
    -- When mining stops (entity depleted or finished), count inventory and move to next
    if not c.entity.mining_state or not c.entity.mining_state.mining then
      -- Mining stopped - count what we got
      local inv_after = c.entity.get_main_inventory().get_contents()
      local added = 0
      for name, data in pairs(inv_after) do
        local before = q.inv_snapshot[name] and q.inv_snapshot[name].count or 0
        added = added + (data.count - before)
      end
      q.harvested = q.harvested + added

      -- Check if target reached
      if q.harvested >= q.target then
        c.entity.mining_state = {mining = false}
        return true
      end

      -- Move to next resource
      q.current = nil
      if not M.start_mining_next(cid) then
        c.entity.mining_state = {mining = false}
        return true
      end
      q.inv_snapshot = c.entity.get_main_inventory().get_contents()
    end

    return false
  end)
end

function M.get_harvest_status(cid)
  local q = storage.harvest_queues[cid]
  if not q then return {active = false} end
  return {
    active = true,
    harvested = q.harvested,
    target = q.target,
    remaining = #q.entities,
    mining = q.current ~= nil
  }
end

function M.stop_harvest(cid)
  local q = storage.harvest_queues[cid]
  if not q then return {stopped = false} end

  local c = valid_companion(cid)
  if c then c.entity.mining_state = {mining = false} end

  local harvested = q.harvested
  storage.harvest_queues[cid] = nil
  return {stopped = true, harvested = harvested}
end

-- ============ CRAFT ============

function M.start_craft(cid, recipe, count)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  local proto = prototypes.recipe[recipe]
  if not proto then return {error = "Unknown recipe: " .. recipe} end

  local craftable = c.entity.get_craftable_count(recipe)
  if craftable < 1 then return {error = "Missing ingredients"} end

  local actual = math.min(count, craftable)
  local ticks = math.max(MIN_ACTION_TICKS, (proto.energy or 0.5) * 60)

  storage.craft_queues[cid] = {
    recipe = recipe,
    target = actual,
    crafted = 0,
    ticks_per = ticks,
    tick_start = game.tick
  }

  return {started = true, recipe = recipe, target = actual, ticks_per = ticks}
end

function M.tick_craft_queues()
  process_queue("craft_queues", function(cid, q, c)
    local elapsed = game.tick - q.tick_start
    if elapsed < q.ticks_per then return false end

    local crafted = c.entity.begin_crafting{recipe = q.recipe, count = 1}
    if crafted < 1 then return true end

    q.crafted = q.crafted + 1
    q.tick_start = game.tick
    return q.crafted >= q.target
  end)
end

function M.get_craft_status(cid)
  local q = storage.craft_queues[cid]
  if not q then return {active = false} end
  return {
    active = true,
    recipe = q.recipe,
    crafted = q.crafted,
    target = q.target,
    progress = math.floor((game.tick - q.tick_start) / q.ticks_per * 100)
  }
end

function M.stop_craft(cid)
  local q = storage.craft_queues[cid]
  if not q then return {stopped = false} end
  local crafted = q.crafted
  storage.craft_queues[cid] = nil
  return {stopped = true, crafted = crafted}
end

-- ============ BUILD ============

function M.start_build(cid, entity_name, position, direction)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  local dir = direction or defines.direction.north
  local dist = u.distance(c.entity.position, position)
  local reach = c.entity.build_distance or 10

  if dist > reach then
    return {error = "Too far (dist: " .. math.floor(dist) .. ", reach: " .. reach .. ")"}
  end

  local inv = c.entity.get_main_inventory()
  if inv.get_item_count(entity_name) < 1 then
    return {error = "No " .. entity_name .. " in inventory"}
  end

  local surface = c.entity.surface
  if not surface.can_place_entity{name = entity_name, position = position, direction = dir, force = c.entity.force} then
    return {error = "Cannot place here"}
  end

  storage.build_queues[cid] = {
    entity = entity_name,
    position = position,
    direction = dir,
    tick_start = game.tick
  }

  return {started = true, entity = entity_name, position = position}
end

function M.tick_build_queues()
  process_queue("build_queues", function(cid, q, c)
    if game.tick - q.tick_start < BUILD_TICKS then return false end

    local placed = c.entity.surface.create_entity{
      name = q.entity,
      position = q.position,
      direction = q.direction,
      force = c.entity.force
    }
    if placed then c.entity.remove_item{name = q.entity, count = 1} end
    return true
  end)
end

function M.get_build_status(cid)
  local q = storage.build_queues[cid]
  if not q then return {active = false} end
  return {
    active = true,
    entity = q.entity,
    position = q.position,
    progress = math.floor((game.tick - q.tick_start) / BUILD_TICKS * 100)
  }
end

function M.stop_build(cid)
  if not storage.build_queues[cid] then return {stopped = false} end
  storage.build_queues[cid] = nil
  return {stopped = true}
end

-- ============ COMBAT ============

function M.start_combat(cid, target_pos)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end

  local enemies = c.entity.surface.find_entities_filtered{
    position = target_pos,
    radius = 10,
    force = "enemy",
    type = {"unit", "unit-spawner"}
  }
  if #enemies == 0 then return {error = "No enemies"} end

  table.sort(enemies, function(a, b)
    return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position)
  end)

  storage.combat_queues[cid] = {
    targets = enemies,
    current = enemies[1],
    cooldown = 0,
    kills = 0
  }

  return {started = true, targets = #enemies}
end

function M.tick_combat_queues()
  process_queue("combat_queues", function(cid, q, c)
    if q.cooldown > 0 then
      q.cooldown = q.cooldown - TICK_INTERVAL
      return false
    end

    if not q.current or not q.current.valid then
      -- Find next valid target (build new list to avoid mutation during iteration)
      local valid_targets = {}
      for _, t in ipairs(q.targets) do
        if t.valid then valid_targets[#valid_targets + 1] = t end
      end
      q.targets = valid_targets

      if #q.targets == 0 then
        c.entity.shooting_state = {state = defines.shooting.not_shooting}
        return true
      end
      q.current = table.remove(q.targets, 1)
    end

    local dist = u.distance(c.entity.position, q.current.position)

    if dist <= ATTACK_RANGE then
      c.entity.shooting_state = {
        state = defines.shooting.shooting_enemies,
        position = q.current.position
      }
      q.cooldown = ATTACK_COOLDOWN
    else
      c.entity.shooting_state = {state = defines.shooting.not_shooting}
      local dir = u.get_direction(c.entity.position, q.current.position)
      if dir then c.entity.walking_state = {walking = true, direction = dir} end
    end
    return false
  end)
end

function M.get_combat_status(cid)
  local q = storage.combat_queues[cid]
  if not q then return {active = false} end

  local remaining = #q.targets
  if q.current and q.current.valid then remaining = remaining + 1 end

  return {
    active = true,
    targets_remaining = remaining,
    current_target = q.current and q.current.valid and q.current.name or nil
  }
end

function M.stop_combat(cid)
  local q = storage.combat_queues[cid]
  if not q then return {stopped = false} end

  local c = valid_companion(cid)
  if c then
    c.entity.shooting_state = {state = defines.shooting.not_shooting}
    c.entity.walking_state = {walking = false}
  end

  storage.combat_queues[cid] = nil
  return {stopped = true}
end

-- ============ GHOST BUILD (Phase 2: blueprint/line fulfillment) ============
-- Fair-play construction: walk to each entity-ghost (via nav pathfinding),
-- consume the required item from inventory, then revive it. Skip + report any
-- ghost we lack materials for or can't reach.

local function ghost_item(ghost)
  local items = ghost.ghost_prototype.items_to_place_this
  if items and items[1] then return items[1].name, items[1].count or 1 end
  return nil, nil
end

function M.start_ghost_build(cid, ghosts)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end
  local list = {}
  for _, g in ipairs(ghosts) do
    if g and g.valid and g.name == "entity-ghost" then list[#list + 1] = g end
  end
  if #list == 0 then return {error = "No ghosts to build"} end
  storage.ghost_build_queues[cid] = {
    ghosts = list,
    total = #list,
    built = 0,
    blocked = 0,
    blocked_set = {},   -- unit_number -> true (missing material / unreachable / collision)
    missing = {},       -- item name -> count short
    current = nil,
    approaching = false,
  }
  return {started = true, ghosts = #list}
end

function M.tick_ghost_build_queues()
  process_queue("ghost_build_queues", function(cid, q, c)
    local reach = c.entity.build_distance or 10

    -- Pick the nearest still-buildable ghost.
    if not q.current or not q.current.valid then
      q.current = nil
      local best, bd = nil, math.huge
      for _, g in ipairs(q.ghosts) do
        if g.valid and g.name == "entity-ghost" and not q.blocked_set[g.unit_number] then
          local d = u.distance(c.entity.position, g.position)
          if d < bd then bd, best = d, g end
        end
      end
      if not best then return true end   -- nothing left buildable -> done
      q.current = best
      q.approaching = false
    end

    local ghost = q.current
    local dist = u.distance(c.entity.position, ghost.position)

    if dist <= reach then
      local item, count = ghost_item(ghost)
      local inv = c.entity.get_main_inventory()
      if not item then
        q.blocked_set[ghost.unit_number] = true; q.blocked = q.blocked + 1
      elseif inv.get_item_count(item) >= count then
        local _, revived = ghost.revive{raise_revive = true}
        if revived then
          inv.remove{name = item, count = count}
          q.built = q.built + 1
        else
          q.blocked_set[ghost.unit_number] = true; q.blocked = q.blocked + 1
        end
      else
        q.missing[item] = (q.missing[item] or 0) + count
        q.blocked_set[ghost.unit_number] = true; q.blocked = q.blocked + 1
      end
      q.current = nil
    else
      -- Walk toward the ghost (issue nav once; detect unreachable when nav ends).
      if not q.approaching then
        nav.go_to(cid, {x = ghost.position.x, y = ghost.position.y}, {radius = math.max(2, reach - 2)})
        q.approaching = true
      elseif not storage.walking_queues[cid] then
        q.blocked_set[ghost.unit_number] = true; q.blocked = q.blocked + 1
        q.current = nil
      end
    end
    return false
  end)
end

function M.get_ghost_build_status(cid)
  local q = storage.ghost_build_queues[cid]
  if not q then return {active = false} end
  local remaining = 0
  for _, g in ipairs(q.ghosts) do
    if g.valid and g.name == "entity-ghost" and not q.blocked_set[g.unit_number] then
      remaining = remaining + 1
    end
  end
  return {
    active = true,
    total = q.total,
    built = q.built,
    blocked = q.blocked,
    remaining = remaining,
    missing = q.missing,
  }
end

function M.stop_ghost_build(cid)
  local q = storage.ghost_build_queues[cid]
  if not q then return {stopped = false} end
  local built = q.built
  storage.ghost_build_queues[cid] = nil
  return {stopped = true, built = built}
end

-- ============ LOGISTICS (Phase 3: haul + refuel) ============
-- Shared fair-play helpers: physically walk (nav), take/give items one entity
-- at a time, bounded by inventory and reach.

-- Nearest non-self entity to a position (the source/dest/burner the order refers to).
local function nearest_entity_at(c, pos, radius)
  local es = c.entity.surface.find_entities_filtered{position = pos, radius = radius or 3, force = c.entity.force}
  local best, bd = nil, math.huge
  for _, e in ipairs(es) do
    if e.valid and e ~= c.entity then
      local d = u.distance(e.position, pos)
      if d < bd then bd, best = d, e end
    end
  end
  return best
end

-- Pull up to `max` of an item from an entity's output/chest inventories into the companion.
local function take_item_into(c, ent, item, max)
  local inv_c = c.entity.get_main_inventory()
  local taken = 0
  local slots = {defines.inventory.chest, defines.inventory.furnace_result,
                 defines.inventory.assembling_machine_output, defines.inventory.car_trunk}
  for _, it in ipairs(slots) do
    if taken >= max then break end
    local src = ent.get_inventory(it)
    if src then
      local avail = src.get_item_count(item)
      if avail > 0 then
        local want = math.min(max - taken, avail)
        local moved = inv_c.insert{name = item, count = want}
        if moved > 0 then src.remove{name = item, count = moved}; taken = taken + moved end
      end
    end
  end
  return taken
end

-- Push up to `max` of an item from the companion into an entity (auto-routes to input/fuel/etc).
local function give_item_from(c, ent, item, max)
  local inv_c = c.entity.get_main_inventory()
  local have = inv_c.get_item_count(item)
  if have == 0 or max <= 0 then return 0 end
  local inserted = ent.insert{name = item, count = math.min(max, have)}
  if inserted > 0 then inv_c.remove{name = item, count = inserted} end
  return inserted
end

-- Travel toward target via nav. Returns true (in reach), false (en route), nil (unreachable).
-- Uses state.moving so nav is issued once per leg.
local function travel(cid, c, target, reach, state)
  if u.distance(c.entity.position, target) <= reach then
    state.moving = false
    return true
  end
  if not state.moving then
    nav.go_to(cid, {x = target.x, y = target.y}, {radius = math.max(2, reach - 2)})
    state.moving = true
    return false
  elseif not storage.walking_queues[cid] then
    state.moving = false      -- nav finished but still out of reach -> unreachable
    return nil
  end
  return false
end

local function logistics_done(cid, task, reason, count)
  storage.logistics_last = storage.logistics_last or {}
  storage.logistics_last[cid] = {task = task, reason = reason, count = count, tick = game.tick}
  return true
end

-- ---- HAUL: move an item from source position to dest position, looping ----

function M.start_haul(cid, item, source, dest, quota)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end
  storage.haul_queues[cid] = {
    item = item, source = source, dest = dest,
    quota = quota or 0,        -- <= 0 means endless (until source empty)
    delivered = 0, phase = "to_source", moving = false, idle = 0,
  }
  return {started = true, item = item, quota = quota or 0}
end

function M.tick_haul_queues()
  process_queue("haul_queues", function(cid, q, c)
    local reach = c.entity.reach_distance or 10
    local inv = c.entity.get_main_inventory()
    local carried = inv.get_item_count(q.item)

    if q.phase == "to_source" then
      local r = travel(cid, c, q.source, reach, q)
      if r == true then q.phase = "loading"
      elseif r == nil then return logistics_done(cid, "haul", "source unreachable", q.delivered) end

    elseif q.phase == "loading" then
      local ent = nearest_entity_at(c, q.source, 3)
      if not ent then return logistics_done(cid, "haul", "no source entity", q.delivered) end
      local remaining = (q.quota > 0) and (q.quota - q.delivered - carried) or math.huge
      if remaining <= 0 then
        q.phase = "to_dest"
      else
        take_item_into(c, ent, q.item, math.min(remaining, 1000000))
        if inv.get_item_count(q.item) > 0 then
          q.idle = 0; q.phase = "to_dest"
        else
          q.idle = q.idle + 1
          if q.idle > 20 then return logistics_done(cid, "haul", "source empty", q.delivered) end
        end
      end

    elseif q.phase == "to_dest" then
      local r = travel(cid, c, q.dest, reach, q)
      if r == true then q.phase = "unloading"
      elseif r == nil then return logistics_done(cid, "haul", "dest unreachable", q.delivered) end

    elseif q.phase == "unloading" then
      local ent = nearest_entity_at(c, q.dest, 3)
      if not ent then return logistics_done(cid, "haul", "no dest entity", q.delivered) end
      local gave = give_item_from(c, ent, q.item, carried)
      q.delivered = q.delivered + gave
      if gave == 0 then
        q.idle = q.idle + 1
        if q.idle > 20 then return logistics_done(cid, "haul", "dest full", q.delivered) end
      else
        q.idle = 0
        if q.quota > 0 and q.delivered >= q.quota then
          return logistics_done(cid, "haul", "quota reached", q.delivered)
        end
        q.phase = "to_source"
      end
    end
    return false
  end)
end

function M.get_haul_status(cid)
  local q = storage.haul_queues[cid]
  if not q then return {active = false} end
  return {active = true, item = q.item, delivered = q.delivered, quota = q.quota, phase = q.phase}
end

function M.stop_haul(cid)
  if not storage.haul_queues[cid] then return {stopped = false} end
  local d = storage.haul_queues[cid].delivered
  storage.haul_queues[cid] = nil
  return {stopped = true, delivered = d}
end

-- ---- REFUEL: keep burners in an area topped up from inventory (endless) ----

local REFUEL_TYPES = {"furnace", "boiler", "burner-inserter", "mining-drill",
                      "car", "locomotive", "reactor", "burner-generator"}
local REFUEL_COOLDOWN = 600   -- ticks before re-servicing the same burner

function M.start_refuel(cid, fuel, center, radius)
  local c = valid_companion(cid)
  if not c then return {error = "Invalid companion"} end
  storage.refuel_queues[cid] = {
    fuel = fuel, center = center, radius = radius or 20,
    amount = 5, refueled = 0, current = nil, moving = false,
    serviced = {}, idle = 0,
  }
  return {started = true, fuel = fuel, radius = radius or 20}
end

function M.tick_refuel_queues()
  process_queue("refuel_queues", function(cid, q, c)
    local reach = c.entity.reach_distance or 10
    local inv = c.entity.get_main_inventory()
    if inv.get_item_count(q.fuel) == 0 then
      return logistics_done(cid, "refuel", "out of fuel", q.refueled)
    end

    if not q.current or not q.current.valid then
      q.current = nil
      local cands = c.entity.surface.find_entities_filtered{
        position = q.center, radius = q.radius, force = c.entity.force, type = REFUEL_TYPES
      }
      local best, bd = nil, math.huge
      for _, e in ipairs(cands) do
        local fi = e.valid and e.get_fuel_inventory() or nil
        if fi and fi.can_insert{name = q.fuel, count = 1} then
          local last = q.serviced[e.unit_number]
          if not last or (game.tick - last) > REFUEL_COOLDOWN then
            local d = u.distance(c.entity.position, e.position)
            if d < bd then bd, best = d, e end
          end
        end
      end
      if not best then return false end   -- nothing needs fuel right now; keep watching (endless)
      q.current = best
      q.moving = false
    end

    local r = travel(cid, c, q.current.position, reach, q)
    if r == true then
      local fi = q.current.get_fuel_inventory()
      if fi then
        local want = math.min(q.amount, inv.get_item_count(q.fuel))
        local ins = fi.insert{name = q.fuel, count = want}
        if ins > 0 then inv.remove{name = q.fuel, count = ins}; q.refueled = q.refueled + ins end
      end
      q.serviced[q.current.unit_number] = game.tick
      q.current = nil
    elseif r == nil then
      q.serviced[q.current.unit_number] = game.tick   -- unreachable, skip for now
      q.current = nil
    end
    return false
  end)
end

function M.get_refuel_status(cid)
  local q = storage.refuel_queues[cid]
  if not q then return {active = false} end
  return {active = true, fuel = q.fuel, refueled = q.refueled, radius = q.radius}
end

function M.stop_refuel(cid)
  if not storage.refuel_queues[cid] then return {stopped = false} end
  local r = storage.refuel_queues[cid].refueled
  storage.refuel_queues[cid] = nil
  return {stopped = true, refueled = r}
end

return M
