-- AI Companion v0.7.0 - Action commands
local u = require("commands.init")
local nav = require("commands.navigation")
local queues = require("commands.queues")

commands.add_command("fac_action_attack", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+([%d.-]+)%s+([%d.-]+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not x or not y then u.error_response("Invalid coordinates"); return end

    -- STOP WALKING - Clear walking queue so attack can take priority
    storage.walking_queues[id] = nil
    c.entity.walking_state = {walking = false}

    local target_pos = {x = x, y = y}
    local targets = c.entity.surface.find_entities_filtered{position = target_pos, radius = 2, limit = 1}
    local t = targets[1]
    if t and t.valid and t ~= c.entity and t.health then
      c.entity.shooting_state = {state = defines.shooting.shooting_enemies, position = t.position}
      u.json_response({id = id, attacking = true, target = t.name, position = {x = t.position.x, y = t.position.y}})
    else
      c.entity.shooting_state = {state = defines.shooting.shooting_enemies, position = target_pos}
      u.json_response({id = id, attacking = true, target = "ground", position = target_pos})
    end
  end)
end)

commands.add_command("fac_action_flee", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local dist = tonumber(args[2]) or 30
    local pos = c.entity.position
    local enemies = c.entity.surface.find_entities_filtered{type = {"unit", "unit-spawner", "turret"}, position = pos, radius = 50, force = "enemy", limit = 5}
    if #enemies == 0 then u.json_response({id = id, fleeing = false, message = "No enemies"}); return end
    local ax, ay = 0, 0
    for _, e in ipairs(enemies) do ax, ay = ax + e.position.x, ay + e.position.y end
    ax, ay = ax / #enemies, ay / #enemies
    local dx, dy = pos.x - ax, pos.y - ay
    local len = math.sqrt(dx*dx + dy*dy)
    if len > 0 then dx, dy = dx / len * dist, dy / len * dist else dx = dist end
    local flee_pos = {x = pos.x + dx, y = pos.y + dy}
    nav.go_to(id, flee_pos)
    u.json_response({id = id, fleeing = true, enemies = #enemies, to = flee_pos})
  end)
end)

-- Patrol a list of waypoints (JSON array of {x,y}), engaging enemies along the way.
commands.add_command("fac_action_patrol", nil, function(cmd)
  u.safe_command(function()
    local first, rest = (cmd.parameter or ""):match("^(%S+)%s+(.+)$")
    local id = u.find_companion(first)
    if not id then u.error_response("Companion not found"); return end
    if not rest then u.error_response('Usage: <id> <points>  JSON [{"x":10,"y":10},...] or "10,10 20,10"'); return end
    local points = {}
    -- Preferred: JSON array of {x,y} (what the MCP tool sends).
    local ok, pts = pcall(helpers.json_to_table, rest)
    if ok and type(pts) == "table" then
      for _, p in ipairs(pts) do
        if p.x and p.y then points[#points + 1] = {x = tonumber(p.x), y = tonumber(p.y)} end
      end
    end
    -- Fallback: space-separated "x,y x,y" pairs (easy to type over RCON/console).
    if #points < 1 then
      for sx, sy in rest:gmatch("(%-?%d+%.?%d*)%s*,%s*(%-?%d+%.?%d*)") do
        points[#points + 1] = {x = tonumber(sx), y = tonumber(sy)}
      end
    end
    if #points < 1 then u.error_response("No valid points (JSON or x,y x,y)"); return end
    local res = queues.start_patrol(id, points)
    res.id = id
    u.json_response(res)
  end)
end)

-- Clear a nest area (Phase 4b): advance + shoot, retreat on low HP / dry ammo,
-- recover via natural regen + own ammo, re-engage. Out of ammo -> stops + reports.
commands.add_command("fac_action_nest_clear", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%d*)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not x or not y then u.error_response("Invalid coordinates"); return end
    local radius = tonumber(args[4]) or 32
    local res = queues.start_nest_clear(id, {x = x, y = y}, radius)
    res.id = id
    u.json_response(res)
  end)
end)

-- Maintain an area (Phase 4c): repair-pack damaged friendly builds + refill
-- ammo-turrets, all from the companion's own inventory. Endless until supplies run out.
commands.add_command("fac_action_repair", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%d*)%s*(%S*)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not x or not y then u.error_response("Invalid coordinates"); return end
    local radius = tonumber(args[4]) or 24
    local ammo = (args[5] ~= "" and args[5]) or nil
    local res = queues.start_repair(id, {x = x, y = y}, radius, ammo)
    res.id = id
    u.json_response(res)
  end)
end)

commands.add_command("fac_action_wololo", nil, function(cmd)
  u.safe_command(function()
    local id, c = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local pos, surf, force = c.entity.position, c.entity.surface, c.entity.force
    local enemies = surf.find_entities_filtered{type = {"unit", "unit-spawner"}, position = pos, radius = 25, limit = 1}
    local t
    for _, e in ipairs(enemies) do if e.valid and e.force.name ~= force.name then t = e; break end end
    if not t then u.json_response({id = id, wololo = false, error = "No enemy"}); return end
    game.print("[" .. u.get_companion_display(id) .. "] WOLOLO!", u.print_color(c.color or u.get_companion_color(id)))
    pcall(function() surf.play_sound{path = "ai-companion-wololo", position = pos} end)
    local old = t.force.name
    t.force = force
    u.json_response({id = id, wololo = true, converted = t.name, from = old})
  end)
end)
