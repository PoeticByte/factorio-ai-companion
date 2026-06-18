-- AI Companion - Unified companion status (Phase 0: observability)
-- Single authoritative "what is this worker doing" view from the Lua side.
-- Aggregates every queue (walking/harvest/craft/build/combat) into one state + task.
local u = require("commands.init")
local queues = require("commands.queues")

-- Derive the active task across all queues. Combat > mining > crafting > building > walking.
local function get_active_task(id)
  if storage.combat_queues and storage.combat_queues[id] then
    local s = queues.get_combat_status(id)
    if s.active then
      return "combat", {targets_remaining = s.targets_remaining, current_target = s.current_target}
    end
  end
  if storage.patrol_queues and storage.patrol_queues[id] then
    local s = queues.get_patrol_status(id)
    if s.active then
      return "patrolling", {points = s.points, index = s.index, phase = s.phase}
    end
  end
  if storage.harvest_queues and storage.harvest_queues[id] then
    local s = queues.get_harvest_status(id)
    if s.active then
      return "mining", {harvested = s.harvested, target = s.target, remaining = s.remaining}
    end
  end
  if storage.craft_queues and storage.craft_queues[id] then
    local s = queues.get_craft_status(id)
    if s.active then
      return "crafting", {recipe = s.recipe, crafted = s.crafted, target = s.target, progress = s.progress}
    end
  end
  if storage.ghost_build_queues and storage.ghost_build_queues[id] then
    local s = queues.get_ghost_build_status(id)
    if s.active then
      return "constructing", {built = s.built, total = s.total, remaining = s.remaining, blocked = s.blocked, missing = s.missing}
    end
  end
  if storage.build_queues and storage.build_queues[id] then
    local s = queues.get_build_status(id)
    if s.active then
      return "building", {entity = s.entity, position = s.position, progress = s.progress}
    end
  end
  if storage.haul_queues and storage.haul_queues[id] then
    local s = queues.get_haul_status(id)
    if s.active then
      return "hauling", {item = s.item, delivered = s.delivered, quota = s.quota, phase = s.phase}
    end
  end
  if storage.refuel_queues and storage.refuel_queues[id] then
    local s = queues.get_refuel_status(id)
    if s.active then
      return "refueling", {fuel = s.fuel, refueled = s.refueled, radius = s.radius}
    end
  end
  if storage.walking_queues and storage.walking_queues[id] then
    local q = storage.walking_queues[id]
    if q.follow_player then
      return "following", {player = q.follow_player, goal = q.goal}
    elseif q.goal then
      return "walking", {goal = {x = q.goal.x, y = q.goal.y}, pending = q.pending == true}
    end
  end
  return "idle", nil
end

-- Top-N inventory items by count, plus slot usage.
local function inventory_summary(c, top_n)
  local inv = c.entity.get_main_inventory()
  if not inv then return {items = {}, used = 0, slots = 0} end
  local items = {}
  for _, item in pairs(inv.get_contents()) do
    items[#items + 1] = {name = item.name, count = item.count}
  end
  table.sort(items, function(a, b) return a.count > b.count end)
  local top = {}
  for i = 1, math.min(top_n or 5, #items) do top[i] = items[i] end
  return {items = top, used = #items, slots = #inv}
end

commands.add_command("fac_companion_status", nil, function(cmd)
  u.safe_command(function()
    local id, c = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local e = c.entity
    local pos = e.position
    local state, task = get_active_task(id)
    u.json_response({
      id = id,
      name = c.name,
      state = state,
      task = task,
      nav = storage.nav_last and storage.nav_last[id] or nil,
      position = {x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10},
      health = {cur = math.floor(e.health), max = math.floor(e.max_health), pct = math.floor(e.health / e.max_health * 100)},
      inventory = inventory_summary(c, 5)
    })
  end)
end)
