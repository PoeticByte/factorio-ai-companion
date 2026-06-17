-- AI Companion - Blueprint / mass construction (Phase 2)
-- Stamp entity-ghosts (from a blueprint string or a programmatic line), then
-- hand them to the ghost-build queue which walks + revives them fairly.
local u = require("commands.init")
local queues = require("commands.queues")

-- Sum the items each ghost needs, for an up-front materials report.
local function materials_needed(ghosts)
  local need = {}
  for _, g in ipairs(ghosts) do
    if g.valid and g.name == "entity-ghost" then
      local items = g.ghost_prototype.items_to_place_this
      if items and items[1] then
        need[items[1].name] = (need[items[1].name] or 0) + (items[1].count or 1)
      end
    end
  end
  return need
end

-- Compare needed materials against the companion's inventory -> shortfall.
local function materials_short(c, need)
  local short, inv = {}, c.entity.get_main_inventory()
  for name, count in pairs(need) do
    local have = inv and inv.get_item_count(name) or 0
    if have < count then short[name] = count - have end
  end
  return short
end

-- Place a blueprint (as ghosts) from an export string, then build it.
commands.add_command("fac_blueprint_place", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%S+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y, bp = tonumber(args[2]), tonumber(args[3]), args[4]
    if not x or not y or not bp then u.error_response("Usage: <id> <x> <y> <blueprint_string>"); return end

    local tmp = game.create_inventory(1)
    local stack = tmp[1]
    local ok = pcall(function() stack.import_stack(bp) end)
    if not ok or not stack.valid_for_read or not stack.is_blueprint then
      tmp.destroy(); u.error_response("Invalid blueprint string"); return
    end
    local ghosts = stack.build_blueprint{
      surface = c.entity.surface,
      force = c.entity.force,
      position = {x = x, y = y},
      force_build = true,
      skip_fog_of_war = false,
    }
    tmp.destroy()
    if not ghosts or #ghosts == 0 then u.error_response("Blueprint placed no ghosts (blocked or empty)"); return end

    local need = materials_needed(ghosts)
    local res = queues.start_ghost_build(id, ghosts)
    res.id = id
    res.materials_needed = need
    res.materials_short = materials_short(c, need)
    u.json_response(res)
  end)
end)

-- Stamp a straight line of N entity-ghosts and build them. dir: 0=N,1=E,2=S,3=W.
commands.add_command("fac_blueprint_line", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%d)%s+(%d+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local entity = args[2]
    local x, y = tonumber(args[3]), tonumber(args[4])
    local dir = tonumber(args[5]) or 1
    local count = math.min(tonumber(args[6]) or 1, 200)
    if not x or not y then u.error_response("Invalid coordinates"); return end

    local proto = prototypes.entity[entity]
    if not proto then u.error_response("Unknown entity: " .. entity); return end
    local tw, th = proto.tile_width or 1, proto.tile_height or 1
    local dir_def = u.dir_map[dir] or defines.direction.north
    local sx, sy = 0, 0
    if dir == 1 then sx = tw elseif dir == 3 then sx = -tw
    elseif dir == 2 then sy = th else sy = -th end

    local surf, force = c.entity.surface, c.entity.force
    local ghosts = {}
    for i = 0, count - 1 do
      local g = surf.create_entity{
        name = "entity-ghost", inner_name = entity,
        position = {x = x + sx * i, y = y + sy * i},
        direction = dir_def, force = force,
      }
      if g then ghosts[#ghosts + 1] = g end
    end
    if #ghosts == 0 then u.error_response("Could not place any ghosts"); return end

    local need = materials_needed(ghosts)
    local res = queues.start_ghost_build(id, ghosts)
    res.id = id
    res.placed = #ghosts
    res.materials_needed = need
    res.materials_short = materials_short(c, need)
    u.json_response(res)
  end)
end)

commands.add_command("fac_blueprint_status", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    u.json_response({id = id, status = queues.get_ghost_build_status(id)})
  end)
end)

commands.add_command("fac_blueprint_stop", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local res = queues.stop_ghost_build(id)
    res.id = id
    u.json_response(res)
  end)
end)
