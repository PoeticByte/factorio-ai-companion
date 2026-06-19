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

-- Factory doctor (Pillar I): scan crafting machines + drills in an area, compute
-- each item's production vs consumption rate (items/sec), and flag bottlenecks
-- (consumed faster than produced). Rates use live crafting_speed (modules/beacons).
commands.add_command("fac_factory_analyze", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 50
    local surf, pos, force = c.entity.surface, c.entity.position, c.entity.force
    local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
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
        local res = d.mining_target.name
        production[res] = (production[res] or 0) + (d.prototype.mining_speed or 0.5)  -- approx items/sec
      end
    end

    local function r2(x) return math.floor(x * 100) / 100 end
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
