-- AI Companion v0.7.0 - World commands
local u = require("commands.init")

local normalize = {copper = "copper-ore", iron = "iron-ore", coal = "coal", stone = "stone", uranium = "uranium-ore"}

commands.add_command("fac_world_nearest", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local what = args[2]
    local name = normalize[what] or what
    local pos = c.entity.position
    local surf = c.entity.surface
    local area = {{pos.x - 200, pos.y - 200}, {pos.x + 200, pos.y + 200}}
    local es
    if what == "wood" or name == "tree" then es = surf.find_entities_filtered{area = area, type = "tree", limit = 100}
    elseif what == "water" then
      local tiles = surf.find_tiles_filtered{area = area, name = {"water", "deepwater"}, limit = 100}
      if #tiles > 0 then
        local closest, min = nil, math.huge
        for _, t in ipairs(tiles) do local d = u.distance(t.position, pos); if d < min then min, closest = d, t.position end end
        u.json_response({id = id, nearest = "water", position = closest, distance = math.floor(min)}); return
      else u.json_response({id = id, error = "Not found"}); return end
    else es = surf.find_entities_filtered{area = area, name = name, limit = 100} end
    if #es == 0 then u.json_response({id = id, error = "Not found"}); return end
    local closest, min = nil, math.huge
    for _, e in ipairs(es) do local d = u.distance(e.position, pos); if d < min then min, closest = d, e end end
    u.json_response({id = id, nearest = closest.name, position = {x = math.floor(closest.position.x), y = math.floor(closest.position.y)}, distance = math.floor(min)})
  end)
end)

commands.add_command("fac_world_scan", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)%s*(%S*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 10
    local filter = args[3] ~= "" and args[3] or nil
    local search = {position = c.entity.position, radius = radius}
    if filter then search.name = filter end
    local es = c.entity.surface.find_entities_filtered(search)
    local result = {}
    for _, e in ipairs(es) do
      if e.valid and e ~= c.entity then
        local r = {name = e.name, type = e.type, position = {x = math.floor(e.position.x * 10) / 10, y = math.floor(e.position.y * 10) / 10}}
        if e.health then r.health = e.health end
        result[#result + 1] = r
      end
    end
    if #result > 50 then local t = {}; for i = 1, 50 do t[i] = result[i] end; result = t end
    u.json_response({id = id, entities = result, count = #result})
  end)
end)

-- Production survey of an area (Phase 5b): resource patches by type (+amount) and
-- friendly buildings by type. Gives the LLM planner a picture of "what's here".
commands.add_command("fac_world_survey", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 100
    local surf, pos = c.entity.surface, c.entity.position
    local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
    local res = {}
    for _, e in ipairs(surf.find_entities_filtered{area = area, type = "resource"}) do
      local r = res[e.name] or {patches = 0, amount = 0}
      r.patches = r.patches + 1
      r.amount = r.amount + (e.amount or 0)
      res[e.name] = r
    end
    local builds = {}
    for _, e in ipairs(surf.find_entities_filtered{area = area, force = c.entity.force}) do
      if e.type ~= "character" then builds[e.type] = (builds[e.type] or 0) + 1 end
    end
    u.json_response({id = id, radius = radius, resources = res, buildings = builds})
  end)
end)

-- Recipe dependency tree (Phase 5b): what ingredients a recipe needs, recursively.
commands.add_command("fac_recipe_deps", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local recipe = args[1]
    local depth = tonumber(args[2]) or 2
    if not prototypes.recipe[recipe] then u.error_response("Unknown recipe: " .. tostring(recipe)); return end
    local function expand(rname, d)
      local p = prototypes.recipe[rname]
      if not p then return nil end
      local out = {}
      for _, ing in pairs(p.ingredients) do
        local entry = {name = ing.name, amount = ing.amount}
        if d > 0 and prototypes.recipe[ing.name] then entry.via = expand(ing.name, d - 1) end
        out[#out + 1] = entry
      end
      return out
    end
    u.json_response({recipe = recipe, ingredients = expand(recipe, depth)})
  end)
end)

-- ===== Factory doctor (Pillar I): production analysis, graph, and auto-fix =====

local function r2(x) return math.floor(x * 100) / 100 end

local function area_around(c, radius)
  local p = c.entity.position
  return {{p.x - radius, p.y - radius}, {p.x + radius, p.y + radius}}
end

-- Production/consumption rates (items/sec) of crafting machines + drills in an area.
local function analyze_area(surf, area, force)
  local production, consumption, machines = {}, {}, 0
  for _, m in ipairs(surf.find_entities_filtered{area = area, type = {"assembling-machine", "furnace"}, force = force}) do
    local recipe = m.valid and m.get_recipe()
    if recipe and m.crafting_speed and recipe.energy and recipe.energy > 0 then
      machines = machines + 1
      local crafts = m.crafting_speed / recipe.energy   -- crafts/sec
      for _, prod in ipairs(recipe.products) do
        local amt = prod.amount or ((prod.amount_min and prod.amount_max) and (prod.amount_min + prod.amount_max) / 2 or 0)
        amt = amt * (prod.probability or 1)
        production[prod.name] = (production[prod.name] or 0) + crafts * amt
      end
      for _, ing in ipairs(recipe.ingredients) do
        consumption[ing.name] = (consumption[ing.name] or 0) + crafts * ing.amount
      end
    end
  end
  for _, d in ipairs(surf.find_entities_filtered{area = area, type = "mining-drill", force = force}) do
    if d.valid and d.mining_target and d.mining_target.valid then
      machines = machines + 1
      production[d.mining_target.name] = (production[d.mining_target.name] or 0) + (d.prototype.mining_speed or 0.5)
    end
  end
  return production, consumption, machines
end

-- A real factory production recipe — not recycling / asteroid-crushing / mining, whose
-- outputs should be treated as raw inputs (ores come from mining, not from a craft chain).
local function prod_recipe(r)
  local cat = r.category or "crafting"
  return not (cat == "recycling" or cat:find("asteroid") or cat:find("crushing") or cat:find("mining"))
end

-- Standard recipe that produces `item` (prefer the same-named one). Does NOT require
-- enabled — planning uses standard recipes even if the tech isn't researched yet.
local function recipe_for(force, item)
  local same = force.recipes[item]
  if same and prod_recipe(same) then return same end
  for _, r in pairs(force.recipes) do
    if prod_recipe(r) then
      for _, p in ipairs(r.products) do if p.name == item then return r end end
    end
  end
  return nil
end

-- Per-machine health: which machines are dead and WHY (unpowered / idle / starved).
local function scan_issues(surf, area, force)
  local unpowered, idle, no_fuel = {}, {}, {}
  local function rec(t, m) if #t < 12 then t[#t + 1] = {name = m.name, x = math.floor(m.position.x), y = math.floor(m.position.y)} end end
  for _, m in ipairs(surf.find_entities_filtered{area = area, force = force,
      type = {"assembling-machine", "furnace", "mining-drill", "lab"}}) do
    if m.valid then
      if m.prototype.electric_energy_source_prototype and not m.is_connected_to_electric_network() then rec(unpowered, m) end
      if m.type == "assembling-machine" and not m.get_recipe() then rec(idle, m) end
      local fi = m.get_fuel_inventory()
      if fi and fi.is_empty() then rec(no_fuel, m) end
    end
  end
  return {unpowered = unpowered, idle = idle, no_fuel = no_fuel}
end

-- Diagnose: net production rate per item + bottlenecks (consumed faster than produced)
-- + per-machine issues (unpowered / idle / no-fuel) — the "why is this dead" view.
commands.add_command("fac_factory_analyze", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 50
    local production, consumption, machines = analyze_area(c.entity.surface, area_around(c, radius), c.entity.force)
    local net, bottlenecks, seen = {}, {}, {}
    for name in pairs(production) do seen[name] = true end
    for name in pairs(consumption) do seen[name] = true end
    for name in pairs(seen) do
      local p, cns = production[name] or 0, consumption[name] or 0
      net[name] = r2(p - cns)
      if cns > 0 and (p - cns) < -0.01 then
        bottlenecks[#bottlenecks + 1] = {item = name, produced = r2(p), consumed = r2(cns), deficit = r2(cns - p)}
      end
    end
    table.sort(bottlenecks, function(a, b) return a.deficit > b.deficit end)
    local issues = scan_issues(c.entity.surface, area_around(c, radius), c.entity.force)
    u.json_response({id = id, radius = radius, machines = machines, net = net,
                     bottlenecks = bottlenecks, issues = issues})
  end)
end)

-- Graph: recipe-level production DAG — for each item, which recipes produce/consume it.
commands.add_command("fac_factory_graph", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 50
    local graph, machines = {}, 0
    for _, m in ipairs(c.entity.surface.find_entities_filtered{area = area_around(c, radius), type = {"assembling-machine", "furnace"}, force = c.entity.force}) do
      local recipe = m.valid and m.get_recipe()
      if recipe then
        machines = machines + 1
        for _, prod in ipairs(recipe.products) do
          graph[prod.name] = graph[prod.name] or {produced_by = {}, consumed_by = {}}
          graph[prod.name].produced_by[recipe.name] = (graph[prod.name].produced_by[recipe.name] or 0) + 1
        end
        for _, ing in ipairs(recipe.ingredients) do
          graph[ing.name] = graph[ing.name] or {produced_by = {}, consumed_by = {}}
          graph[ing.name].consumed_by[recipe.name] = (graph[ing.name].consumed_by[recipe.name] or 0) + 1
        end
      end
    end
    u.json_response({id = id, radius = radius, machines = machines, graph = graph})
  end)
end)

-- Poles the companion may use to extend power, weakest first (cheapest grid join).
local POLE_PRIORITY = {"small-electric-pole", "medium-electric-pole", "big-electric-pole", "substation"}
-- Fuels for a burner machine, best first.
local BURNER_FUELS = {"coal", "solid-fuel", "wood", "carbon", "nuclear-fuel"}

local function find_in_inv(inv, names)
  for _, n in ipairs(names) do if inv.get_item_count(n) > 0 then return n end end
  return nil
end

-- Energize a freshly placed electric machine: if it isn't on a powered network,
-- drop a pole next to it (so its supply area covers the machine) and a connected
-- line of poles toward the nearest existing pole. Fair-play: poles from inventory;
-- Factorio auto-connects poles within wire reach.
local function wire_power(c, machine)
  local e = c.entity
  local surf, force = e.surface, e.force
  if not machine.prototype.electric_energy_source_prototype then return {power = "not electric"} end
  if machine.is_connected_to_electric_network() then return {power = "already connected"} end
  local inv = e.get_main_inventory()
  local pole_item = find_in_inv(inv, POLE_PRIORITY)
  if not pole_item then return {power = "no pole in inventory"} end
  local reach = prototypes.entity[pole_item].get_max_wire_distance() or 7.5

  -- Nearest existing pole to graft the new chain onto.
  local target, td = nil, math.huge
  for _, p in ipairs(surf.find_entities_filtered{position = machine.position, radius = 64, type = "electric-pole", force = force}) do
    if p.valid and p ~= machine then
      local d = u.distance(machine.position, p.position)
      if d < td then td, target = d, p end
    end
  end
  if not target then return {power = "no grid within 64 tiles"} end

  local placed = 0
  local function drop(near)
    if inv.get_item_count(pole_item) < 1 then return nil end
    local spot = surf.find_non_colliding_position(pole_item, near, 5, 0.5)
    if not spot then return nil end
    local pole = surf.create_entity{name = pole_item, position = spot, force = force}
    if not pole then return nil end
    inv.remove{name = pole_item, count = 1}; placed = placed + 1
    return pole
  end

  -- 1) Pole hugging the machine so the machine sits in its supply area.
  local last = drop(machine.position)
  if not last then return {power = "could not place pole"} end
  -- 2) Step toward the target until the chain is within wire reach of it.
  local step = math.max(2, reach - 1)
  local guard = 0
  while u.distance(last.position, target.position) > reach and guard < 24 do
    guard = guard + 1
    local dx, dy = target.position.x - last.position.x, target.position.y - last.position.y
    local len = math.sqrt(dx * dx + dy * dy); if len < 0.01 then break end
    local nxt = drop({x = last.position.x + dx / len * step, y = last.position.y + dy / len * step})
    if not nxt then break end
    last = nxt
  end

  return {power = machine.is_connected_to_electric_network() and "connected" or "poles placed (grid may be unpowered)",
          poles_placed = placed, pole = pole_item}
end

-- Fuel a burner machine from the companion's inventory (electric machines skip this).
local function fuel_burner(c, machine)
  if machine.prototype.electric_energy_source_prototype then return {fuel = "electric"} end
  local fi = machine.get_fuel_inventory()
  if not fi then return {fuel = "no fuel slot"} end
  local inv = c.entity.get_main_inventory()
  local f = find_in_inv(inv, BURNER_FUELS)
  if not f then return {fuel = "none in inventory"} end
  local ins = fi.insert{name = f, count = math.min(5, inv.get_item_count(f))}
  if ins > 0 then inv.remove{name = f, count = ins}; return {fuel = f, inserted = ins} end
  return {fuel = "could not insert"}
end

-- Treat: find the worst fixable bottleneck and, if the companion carries the right
-- machine, place it + set its recipe + ENERGIZE it (wire power / fuel a burner) near
-- the companion. Reports the recipe's inputs so a plan/haul can feed it.
-- Still manual: belt/inserter routing of those inputs.
commands.add_command("fac_factory_fix", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 50
    local e = c.entity
    local production, consumption = analyze_area(e.surface, area_around(c, radius), e.force)
    local target, worst = nil, 0.01
    for name in pairs(consumption) do
      local deficit = (consumption[name] or 0) - (production[name] or 0)
      if deficit > worst then
        local r = recipe_for(e.force, name)
        if r and r.enabled then worst = deficit; target = {item = name, recipe = r, deficit = deficit} end  -- only build what we can actually craft
      end
    end
    if not target then u.json_response({id = id, fixed = false, reason = "no fixable bottleneck"}); return end
    local machine = (target.recipe.category == "smelting") and "stone-furnace" or "assembling-machine-2"
    local inv = e.get_main_inventory()
    if inv.get_item_count(machine) < 1 then
      u.json_response({id = id, fixed = false, bottleneck = target.item, deficit = r2(target.deficit),
        suggest = {build = machine, recipe = target.recipe.name}, reason = "need " .. machine .. " in inventory"}); return
    end
    local spot = e.surface.find_non_colliding_position(machine, e.position, 16, 1)
    if not spot then u.json_response({id = id, fixed = false, reason = "no space nearby"}); return end
    local placed = e.surface.create_entity{name = machine, position = spot, force = e.force}
    if not placed then u.json_response({id = id, fixed = false, reason = "place failed"}); return end
    inv.remove{name = machine, count = 1}
    if machine ~= "stone-furnace" then pcall(function() placed.set_recipe(target.recipe.name) end) end

    local power = wire_power(c, placed)
    local fuel = fuel_burner(c, placed)
    local inputs = {}
    for _, ing in ipairs(target.recipe.ingredients) do inputs[#inputs + 1] = ing.name end

    u.json_response({id = id, fixed = true, bottleneck = target.item, built = machine,
      at = {x = math.floor(spot.x), y = math.floor(spot.y)}, recipe = target.recipe.name,
      power = power, fuel = fuel, needs_inputs = inputs,
      note = "placed + recipe + energized; call factory_wire to add I/O inserters+chests, then haul to feed it"})
  end)
end)

-- Production plan (Pillar I): given a target item + rate/sec, recurse the recipe DAG to
-- compute the rate + (baseline) machine count for every intermediate, and the raw inputs
-- needed. This is the ratio math behind "build me X/s of Y" — the actionable form of the DAG.
commands.add_command("fac_production_plan", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s*([%d.]*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local item = args[2]
    local rate = tonumber(args[3]) or 1
    local force = c.entity.force
    local agg, raw = {}, {}
    local function plan(it, rt, depth)
      local r = recipe_for(force, it)
      if not r or depth > 12 then raw[it] = (raw[it] or 0) + rt; return end
      local pamt = 0
      for _, p in ipairs(r.products) do
        if p.name == it then pamt = p.amount or ((p.amount_min and p.amount_max) and (p.amount_min + p.amount_max) / 2 or 0); break end
      end
      if pamt <= 0 then raw[it] = (raw[it] or 0) + rt; return end
      local crafts = rt / pamt                                   -- crafts/sec needed
      local ref = (r.category == "smelting") and 1 or 0.75       -- baseline machine speed
      local machines = crafts / (ref / r.energy)
      agg[it] = agg[it] or {item = it, rate = 0, recipe = r.name, machines = 0}
      agg[it].rate = agg[it].rate + rt
      agg[it].machines = agg[it].machines + machines
      for _, ing in ipairs(r.ingredients) do plan(ing.name, crafts * ing.amount, depth + 1) end
    end
    plan(item, rate, 0)
    local steps = {}
    for _, s in pairs(agg) do s.rate = r2(s.rate); s.machines = r2(s.machines); steps[#steps + 1] = s end
    table.sort(steps, function(a, b) return a.machines > b.machines end)
    local raws = {}
    for k, v in pairs(raw) do raws[k] = r2(v) end
    u.json_response({id = id, item = item, rate = rate, steps = steps, raw_inputs = raws})
  end)
end)

-- Factory doctor WIRE (Pillar I): turn a placed assembling-machine into a self-feeding
-- station — input inserters pulling from buffer chests into the machine, plus an output
-- inserter into an output chest. Fair-play: inserters+chests come from the companion's
-- inventory. A haul plan/skill then keeps the input chests stocked = supply-chain handoff.
local INSERTER_PREF = {"fast-inserter", "inserter", "long-handed-inserter", "bulk-inserter"}
local CHEST_PREF = {"steel-chest", "iron-chest", "wooden-chest"}

-- Faces around a 3x3 machine centered at (cx,cy): inserter 2 tiles out, buffer chest 3
-- tiles out. An inserter PICKS UP from its `direction` side and DROPS to the opposite
-- side (verified in-game). So an INPUT inserter faces its chest (picks from chest, drops
-- into the machine behind it); the OUTPUT inserter faces the machine (picks the product,
-- drops into the chest behind it).
local INPUT_FACES = {
  {dx = 0,  dy = -2, dir = defines.direction.north, cdx = 0,  cdy = -3},  -- N: pick N chest, drop S into machine
  {dx = -2, dy = 0,  dir = defines.direction.west,  cdx = -3, cdy = 0},   -- W: pick W chest, drop E into machine
  {dx = 2,  dy = 0,  dir = defines.direction.east,  cdx = 3,  cdy = 0},   -- E: pick E chest, drop W into machine
}
local OUTPUT_FACE = {dx = 0, dy = 2, dir = defines.direction.north, cdx = 0, cdy = 3}  -- S: pick N from machine, drop S into chest

local function place_io(surf, force, inv, m, face, ins_item, chest_item, tally, inserters)
  local res = {}
  local ipos = {x = m.position.x + face.dx, y = m.position.y + face.dy}
  local cpos = {x = m.position.x + face.cdx, y = m.position.y + face.cdy}
  if inv.get_item_count(chest_item) >= 1 and surf.can_place_entity{name = chest_item, position = cpos, force = force} then
    if surf.create_entity{name = chest_item, position = cpos, force = force} then
      inv.remove{name = chest_item, count = 1}; tally.chests = tally.chests + 1; res.chest = chest_item
    end
  else res.chest = "skip" end
  if inv.get_item_count(ins_item) >= 1 and surf.can_place_entity{name = ins_item, position = ipos, direction = face.dir, force = force} then
    local it = surf.create_entity{name = ins_item, position = ipos, direction = face.dir, force = force}
    if it then
      inv.remove{name = ins_item, count = 1}; tally.inserters = tally.inserters + 1; res.inserter = ins_item
      inserters[#inserters + 1] = it
    end
  else res.inserter = "skip" end
  return res
end

-- Inserters need power too. Drop a pole next to any placed inserter that isn't on a
-- powered network (it connects to the station's existing poles within wire reach).
local function ensure_inserters_powered(surf, force, inv, inserters)
  local pole = find_in_inv(inv, POLE_PRIORITY)
  if not pole then return 0 end
  local placed = 0
  for _, it in ipairs(inserters) do
    if it.valid and not it.is_connected_to_electric_network() and inv.get_item_count(pole) >= 1 then
      local spot = surf.find_non_colliding_position(pole, it.position, 4, 0.5)
      if spot and surf.create_entity{name = pole, position = spot, force = force} then
        inv.remove{name = pole, count = 1}; placed = placed + 1
      end
    end
  end
  return placed
end

-- Wire input inserters←buffer chests + an output inserter→chest around a machine.
-- Furnaces (auto-recipe) get 1 input; assemblers get one input per solid ingredient.
-- Reports input_chest/output_chest tiles so a haul plan knows where to feed/collect.
local function wire_machine_io(surf, force, inv, m)
  local ins_item = find_in_inv(inv, INSERTER_PREF)
  local chest_item = find_in_inv(inv, CHEST_PREF)
  if not ins_item or not chest_item then
    return {ok = false, reason = "need an inserter + a chest in inventory",
            have_inserter = ins_item or false, have_chest = chest_item or false}
  end
  local n_inputs
  if m.type == "furnace" then
    n_inputs = 1
  else
    local r = m.get_recipe()
    if not r then return {ok = false, reason = "machine has no recipe"} end
    n_inputs = 0
    for _, ing in ipairs(r.ingredients) do if ing.type ~= "fluid" then n_inputs = n_inputs + 1 end end
  end
  n_inputs = math.min(math.max(n_inputs, 1), #INPUT_FACES)

  local tally, detail, inserters = {inserters = 0, chests = 0}, {}, {}
  for i = 1, n_inputs do
    local r = place_io(surf, force, inv, m, INPUT_FACES[i], ins_item, chest_item, tally, inserters); r.role = "input"
    detail[#detail + 1] = r
  end
  local ro = place_io(surf, force, inv, m, OUTPUT_FACE, ins_item, chest_item, tally, inserters); ro.role = "output"
  detail[#detail + 1] = ro
  tally.poles_for_inserters = ensure_inserters_powered(surf, force, inv, inserters)
  return {ok = tally.inserters > 0, placed = tally, inserter = ins_item, chest = chest_item, detail = detail,
          input_chest = {x = math.floor(m.position.x + INPUT_FACES[1].cdx), y = math.floor(m.position.y + INPUT_FACES[1].cdy)},
          output_chest = {x = math.floor(m.position.x + OUTPUT_FACE.cdx), y = math.floor(m.position.y + OUTPUT_FACE.cdy)}}
end

commands.add_command("fac_factory_wire", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 16
    local e = c.entity
    local m, md = nil, math.huge
    for _, x in ipairs(e.surface.find_entities_filtered{position = e.position, radius = radius, type = "assembling-machine", force = e.force}) do
      if x.valid and x.get_recipe() then
        local d = u.distance(e.position, x.position)
        if d < md then md, m = d, x end
      end
    end
    if not m then u.json_response({id = id, wired = false, reason = "no assembling-machine with a recipe within " .. radius}); return end
    local io = wire_machine_io(e.surface, e.force, e.get_main_inventory(), m)
    u.json_response({id = id, wired = io.ok, machine = m.name, recipe = m.get_recipe().name,
      at = {x = math.floor(m.position.x), y = math.floor(m.position.y)}, io = io,
      note = "stock io.input_chest with ingredients (haul) — the machine runs and fills io.output_chest"})
  end)
end)

-- One-shot "build a complete working station for <recipe>" (Pillar I capstone):
-- place the right machine near the companion + set recipe + energize (pole line / fuel)
-- + wire I/O inserters & buffer chests. Returns io.input_chest so the orchestrator can
-- immediately haul ingredients to it. Chains factory_fix's placement + factory_wire.
commands.add_command("fac_build_station", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local recipe_name = args[2]
    local e = c.entity
    local recipe = e.force.recipes[recipe_name] or prototypes.recipe[recipe_name]
    if not recipe then u.error_response("Unknown recipe: " .. tostring(recipe_name)); return end
    local machine = (recipe.category == "smelting") and "stone-furnace" or "assembling-machine-2"
    local inv = e.get_main_inventory()
    if inv.get_item_count(machine) < 1 then
      u.json_response({id = id, built = false, recipe = recipe_name, reason = "need " .. machine .. " in inventory"}); return
    end
    local spot = e.surface.find_non_colliding_position(machine, e.position, 16, 1)
    if not spot then u.json_response({id = id, built = false, reason = "no space nearby"}); return end
    local m = e.surface.create_entity{name = machine, position = spot, force = e.force}
    if not m then u.json_response({id = id, built = false, reason = "place failed"}); return end
    inv.remove{name = machine, count = 1}
    if machine ~= "stone-furnace" then pcall(function() m.set_recipe(recipe_name) end) end
    local power = wire_power(c, m)
    local fuel = fuel_burner(c, m)
    local io = wire_machine_io(e.surface, e.force, inv, m)
    u.json_response({id = id, built = true, machine = machine, recipe = recipe_name,
      at = {x = math.floor(spot.x), y = math.floor(spot.y)}, power = power, fuel = fuel, io = io,
      note = "haul ingredients to io.input_chest; products collect in io.output_chest"})
  end)
end)
