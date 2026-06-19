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

-- Diagnose: net production rate per item + bottlenecks (consumed faster than produced).
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
    u.json_response({id = id, radius = radius, machines = machines, net = net, bottlenecks = bottlenecks})
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

-- Treat: find the worst fixable bottleneck and, if the companion carries the right
-- machine, place it + set its recipe near the companion. Otherwise report a suggestion.
-- MVP: places the machine only — inputs/power still need wiring.
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
    u.json_response({id = id, fixed = true, bottleneck = target.item, built = machine,
      at = {x = math.floor(spot.x), y = math.floor(spot.y)}, recipe = target.recipe.name,
      note = "placed + recipe set; inputs/power still need wiring"})
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
