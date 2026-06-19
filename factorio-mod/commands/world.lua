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
