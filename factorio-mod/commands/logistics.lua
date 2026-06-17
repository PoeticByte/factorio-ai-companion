-- AI Companion - Logistics crew (Phase 3): haul + refuel
-- Thin command wrappers; the looping state machines live in commands.queues.
local u = require("commands.init")
local queues = require("commands.queues")

-- haul <id> <item> <sx> <sy> <dx> <dy> [quota]
commands.add_command("fac_haul", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args(
      "^(%S+)%s+(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%-?%d*)$",
      cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local item = args[2]
    local sx, sy = tonumber(args[3]), tonumber(args[4])
    local dx, dy = tonumber(args[5]), tonumber(args[6])
    local quota = tonumber(args[7]) or 0
    if not (item and sx and sy and dx and dy) then
      u.error_response("Usage: <id> <item> <sx> <sy> <dx> <dy> [quota]"); return
    end
    local res = queues.start_haul(id, item, {x = sx, y = sy}, {x = dx, y = dy}, quota)
    res.id = id
    u.json_response(res)
  end)
end)

commands.add_command("fac_haul_status", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    u.json_response({id = id, status = queues.get_haul_status(id)})
  end)
end)

commands.add_command("fac_haul_stop", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local res = queues.stop_haul(id); res.id = id
    u.json_response(res)
  end)
end)

-- refuel <id> <fuel> <x> <y> [radius]
commands.add_command("fac_refuel", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local fuel = args[2]
    local x, y = tonumber(args[3]), tonumber(args[4])
    local radius = tonumber(args[5]) or 20
    if not (fuel and x and y) then u.error_response("Usage: <id> <fuel> <x> <y> [radius]"); return end
    local res = queues.start_refuel(id, fuel, {x = x, y = y}, radius)
    res.id = id
    u.json_response(res)
  end)
end)

commands.add_command("fac_refuel_status", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    u.json_response({id = id, status = queues.get_refuel_status(id)})
  end)
end)

commands.add_command("fac_refuel_stop", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    local res = queues.stop_refuel(id); res.id = id
    u.json_response(res)
  end)
end)
