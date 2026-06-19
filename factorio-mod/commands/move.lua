-- AI Companion v0.7.0 - Move commands (pathfinding via commands.navigation)
local u = require("commands.init")
local nav = require("commands.navigation")
local orch = require("commands.orchestration")

commands.add_command("fac_move_to", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+([%d.-]+)%s+([%d.-]+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not x or not y then u.error_response("Invalid coordinates"); return end
    local result = nav.go_to(id, {x = x, y = y})
    result.id = id
    u.json_response(result)
  end)
end)

commands.add_command("fac_move_follow", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(.+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local pname = args[2]
    local result = nav.follow(id, pname)
    if result.error then u.error_response(result.error); return end
    result.id = id
    u.json_response(result)
  end)
end)

commands.add_command("fac_move_stop", nil, function(cmd)
  u.safe_command(function()
    local id = u.find_companion(cmd.parameter)
    if not id then u.error_response("Companion not found"); return end
    if storage.patrol_queues then storage.patrol_queues[id] = nil end  -- moving cancels patrol
    if storage.nest_clear_queues then storage.nest_clear_queues[id] = nil end
    if storage.repair_queues then storage.repair_queues[id] = nil end
    orch.release_all(id)
    nav.stop(id)
    u.json_response({id = id, stopped = true})
  end)
end)
