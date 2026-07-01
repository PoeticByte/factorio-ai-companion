-- AI Companion - Standing roles + auto-response (Phase 5c)
-- Bind a companion to a role over an area; a throttled tick re-triggers the matching
-- skill when conditions warrant: guard->nest_clear, refueler->refuel, maintainer->repair.
-- Roles persist across saves. Companion must carry its own supplies (fuel/ammo/repair-packs).
local u = require("commands.init")
local queues = require("commands.queues")
local memory = require("commands.memory")

local M = {}

function M.init()
  storage.roles = storage.roles or {}
end

-- Already running some task? Don't re-trigger while busy.
local function busy(cid)
  local q = storage
  if q.harvest_queues and q.harvest_queues[cid] then return true end
  if q.ghost_build_queues and q.ghost_build_queues[cid] then return true end
  if q.haul_queues and q.haul_queues[cid] then return true end
  if q.refuel_queues and q.refuel_queues[cid] then return true end
  if q.nest_clear_queues and q.nest_clear_queues[cid] then return true end
  if q.repair_queues and q.repair_queues[cid] then return true end
  if q.patrol_queues and q.patrol_queues[cid] then return true end
  if q.combat_queues and q.combat_queues[cid] then return true end
  if q.walking_queues and q.walking_queues[cid] then return true end
  return false
end

function M.assign_role(cid, role, center, radius, item)
  local c = u.get_companion(cid)
  if not c or not c.entity or not c.entity.valid then return {error = "Invalid companion"} end
  storage.roles = storage.roles or {}
  storage.roles[cid] = {role = role, center = center, radius = radius or 24, item = item}
  return {assigned = true, role = role, center = center, radius = radius or 24, item = item}
end

-- Continuous courier role: ferry `item` from `source` to `dest` whenever source has it.
function M.assign_courier(cid, item, source, dest, batch)
  local c = u.get_companion(cid)
  if not c or not c.entity or not c.entity.valid then return {error = "Invalid companion"} end
  storage.roles = storage.roles or {}
  storage.roles[cid] = {role = "courier", item = item, source = source, dest = dest, batch = batch or 50}
  return {assigned = true, role = "courier", item = item, source = source, dest = dest, batch = batch or 50}
end

function M.clear_role(cid)
  if storage.roles and storage.roles[cid] then storage.roles[cid] = nil; return {cleared = true} end
  return {cleared = false}
end

-- Throttled from control.lua (~every 30 ticks). Each idle role checks its area and
-- fires the matching skill; the skill then runs on its own queue/tick.
function M.tick_roles()
  if not storage.roles then return end
  for cid, role in pairs(storage.roles) do
    local c = u.get_companion(cid)
    if not c or not c.entity or not c.entity.valid then
      storage.roles[cid] = nil
    elseif role.role == "scout" then
      -- Passive continuous map-learning: survey+remember around the companion every
      -- ~10s, EVEN while busy (so a scout following the player maps as it travels).
      if (game.tick - (role.last_survey or 0)) > 600 then
        role.last_survey = game.tick
        memory.survey(cid, c, role.radius or 100)
      end
    elseif not busy(cid) then
      local e = c.entity
      local surf = e.surface
      if role.role == "guard" then
        local foes = surf.count_entities_filtered{position = role.center, radius = role.radius,
          force = "enemy", type = {"unit", "unit-spawner", "turret"}}
        if foes > 0 then queues.start_nest_clear(cid, role.center, role.radius) end

      elseif role.role == "refueler" and role.item then
        local lo = false
        for _, b in ipairs(surf.find_entities_filtered{position = role.center, radius = role.radius,
            type = {"furnace", "boiler", "mining-drill", "burner-inserter", "reactor"}}) do
          local fi = b.valid and b.get_fuel_inventory()
          if fi and fi.get_item_count(role.item) < 1 then lo = true; break end
        end
        if lo then queues.start_refuel(cid, role.item, role.center, role.radius) end

      elseif role.role == "maintainer" then
        local dirty = false
        for _, x in ipairs(surf.find_entities_filtered{position = role.center, radius = role.radius, force = e.force}) do
          if x.valid and x ~= e and x.type ~= "character" then
            if x.health and x.max_health and x.health < x.max_health - 1 then dirty = true; break end
            if role.item and x.type == "ammo-turret" then
              local ti = x.get_inventory(defines.inventory.turret_ammo)
              if ti and ti.can_insert{name = role.item, count = 1} then dirty = true; break end
            end
          end
        end
        if dirty then queues.start_repair(cid, role.center, role.radius, role.item) end

      elseif role.role == "courier" and role.item and role.source and role.dest then
        -- Continuous logistics: ferry a batch whenever the source has the item.
        -- Re-triggers each idle tick (like refueler) -> a self-sustaining supply line
        -- between two stations (e.g. furnace output_chest -> assembler input_chest).
        local has = false
        for _, ent in ipairs(surf.find_entities_filtered{position = role.source, radius = 3, force = e.force}) do
          if ent.valid and ent ~= e then
            local oi = ent.get_output_inventory and ent.get_output_inventory()
            if oi and oi.get_item_count(role.item) > 0 then has = true; break end
          end
        end
        if has then queues.start_haul(cid, role.item, role.source, role.dest, role.batch or 50) end
      end
    end
  end
end

function M.list_roles()
  local out = {}
  if storage.roles then
    for cid, r in pairs(storage.roles) do
      out[#out + 1] = {cid = cid, role = r.role, center = r.center, radius = r.radius,
                       item = r.item, source = r.source, dest = r.dest}
    end
  end
  return out
end

-- ---- Commands ----

commands.add_command("fac_assign_role", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%d*)%s*(%S*)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local role = args[2]
    if role ~= "guard" and role ~= "refueler" and role ~= "maintainer" and role ~= "scout" then
      u.error_response("role must be guard|refueler|maintainer|scout"); return
    end
    local x, y = tonumber(args[3]), tonumber(args[4])
    if not x or not y then u.error_response("Invalid coordinates"); return end
    local radius = tonumber(args[5]) or 24
    local item = (args[6] ~= "" and args[6]) or nil
    local res = M.assign_role(id, role, {x = x, y = y}, radius, item)
    res.id = id
    u.json_response(res)
  end)
end)

-- "fac_assign_courier <id> <item> <sx> <sy> <dx> <dy> [batch]"
commands.add_command("fac_assign_courier", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%d*)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local item = args[2]
    local sx, sy, dx, dy = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if not (item and sx and sy and dx and dy) then u.error_response("Usage: <id> <item> <sx> <sy> <dx> <dy> [batch]"); return end
    local batch = tonumber(args[7]) or 50
    local res = M.assign_courier(id, item, {x = sx, y = sy}, {x = dx, y = dy}, batch)
    res.id = id
    u.json_response(res)
  end)
end)

commands.add_command("fac_clear_role", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local res = M.clear_role(id)
    res.id = id
    u.json_response(res)
  end)
end)

commands.add_command("fac_roles", nil, function(cmd)
  u.safe_command(function()
    local list = M.list_roles()
    u.json_response({roles = list, count = #list})
  end)
end)

return M
