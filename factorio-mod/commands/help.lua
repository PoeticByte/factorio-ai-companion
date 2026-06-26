-- AI Companion - Help
local u = require("commands.init")

-- Version command
commands.add_command("fac_version", nil, function()
  local version = script.active_mods["ai-companion"] or "unknown"
  u.json_response({version = version, factorio = script.active_mods["base"] or "unknown"})
  game.print("[AI Companion] v" .. version, u.print_color(u.COLORS.system))
end)

commands.add_command("fac_help", nil, function()
  local version = script.active_mods["ai-companion"] or "unknown"
  u.json_response({
    version = version,
    categories = {"chat", "companion", "move", "resource", "item", "building", "blueprint",
                  "world", "logistics", "combat", "research", "factory", "orchestration",
                  "plan", "memory", "context", "meta"},
    chat = {"get", "say"},
    companion = {"spawn", "list", "status", "stop", "stop_all", "position", "inventory", "health", "disappear"},
    move = {"to", "follow", "stop"},
    resource = {"list", "nearest", "mine", "mine_status", "mine_stop"},
    item = {"craft", "craft_status", "craft_stop", "pick", "recipes"},
    building = {"place", "place_start", "place_status", "remove", "rotate", "info", "recipe", "fuel", "fill", "empty", "can_place"},
    blueprint = {"place", "line", "status", "stop"},
    world = {"scan", "nearest", "survey"},
    logistics = {"haul", "haul_status", "haul_stop", "refuel", "refuel_status", "refuel_stop"},
    combat = {"attack", "defend", "flee", "patrol", "wololo", "nest_clear", "repair"},
    research = {"get", "set", "progress", "tech_path"},
    factory = {"analyze", "graph", "fix", "production_plan", "recipe_deps"},
    orchestration = {"reserve", "release", "reservations", "assign_role", "clear_role", "roles"},
    plan = {"create (auto + DAG deps)", "status", "step_done", "run on|off"},
    memory = {"remember", "recall", "forget", "list", "goto"},
    context = {"clear", "check"},
    meta = {"version", "help", "overview", "session_status"},
    player = {"/fac <msg>", "/fac <id> <msg>", "/fac spawn", "/fac list", "/fac kill", "/fac clear", "/fac name"}
  })
end)
