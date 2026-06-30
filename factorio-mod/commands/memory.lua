-- AI Companion - Persistent buddy memory (Pillar III: "a buddy who knows you")
-- A durable, save-surviving store the companion keeps ABOUT the player and world:
--   locations  named places (iron mine, main base, north wall) -> {x,y,kind,note}
--   prefs      free-form playstyle/layout preferences key -> value
--   notes      timestamped observations (optionally pinned to a position)
-- The orchestrator reads this at session start (memory_list/recall) and writes to it
-- as it learns, so the companion "remembers you" across play sessions. Distinct from
-- the engine's transient queues — this is knowledge, not a task.
local u = require("commands.init")
local nav = require("commands.navigation")

local M = {}

local MAX_NOTES = 200

function M.init()
  storage.memory = storage.memory or {}
  storage.memory.locations = storage.memory.locations or {}   -- lower(name) -> entry
  storage.memory.prefs = storage.memory.prefs or {}           -- lower(key)  -> entry
  storage.memory.notes = storage.memory.notes or {}           -- array
  storage.memory.tags = storage.memory.tags or {}             -- lower(name) -> LuaCustomChartTag
end

local function loc_entry(name, kind, x, y, note)
  return {name = name, kind = kind or "custom", x = math.floor(x), y = math.floor(y),
          note = note, tick = game.tick}
end

-- Surface + force to chart a location on (the companion's if given, else nauvis/player).
local function tag_surface_force(companionId)
  if companionId ~= nil then
    local _, c = u.find_companion(companionId)
    if c then return c.entity.surface, c.entity.force end
  end
  return (game.surfaces and game.surfaces.nauvis) or game.get_surface(1), game.forces.player
end

-- Drop (or replace) a map chart tag so the remembered place shows on the map.
local function set_location_tag(key, entry, companionId)
  storage.memory.tags = storage.memory.tags or {}
  local old = storage.memory.tags[key]
  if old and old.valid then old.destroy() end
  storage.memory.tags[key] = nil
  local surf, force = tag_surface_force(companionId)
  if not (surf and force) then return end
  local ok, tag = pcall(function()
    return force.add_chart_tag(surf, {position = {x = entry.x, y = entry.y},
                                      text = entry.name .. " [" .. entry.kind .. "]"})
  end)
  if ok and tag then storage.memory.tags[key] = tag end
end

local function clear_location_tag(key)
  local t = storage.memory.tags and storage.memory.tags[key]
  if t then
    if t.valid then t.destroy() end
    storage.memory.tags[key] = nil
  end
end

-- ---- Remember: store/update one memory. JSON-driven for flexible shapes. ----
-- {type:"location", name, kind?, x?, y?, companionId?, note?}  (x/y or companionId)
-- {type:"pref", key, value}
-- {type:"note", text, x?, y?}
commands.add_command("fac_memory_remember", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local ok, d = pcall(helpers.json_to_table, cmd.parameter or "")
    if not ok or type(d) ~= "table" or not d.type then
      u.error_response('Usage: JSON {"type":"location|pref|note", ...}'); return
    end

    if d.type == "location" then
      if type(d.name) ~= "string" then u.error_response("location needs name"); return end
      local x, y = d.x, d.y
      if (not x or not y) and d.companionId ~= nil then
        local _, c = u.find_companion(d.companionId)
        if c then x, y = c.entity.position.x, c.entity.position.y end
      end
      if not x or not y then u.error_response("location needs x,y or a companionId to capture position"); return end
      local key = d.name:lower()
      local entry = loc_entry(d.name, d.kind, x, y, d.note)
      storage.memory.locations[key] = entry
      set_location_tag(key, entry, d.companionId)
      u.json_response({remembered = "location", entry = entry, charted = storage.memory.tags[key] ~= nil})

    elseif d.type == "pref" then
      if type(d.key) ~= "string" then u.error_response("pref needs key"); return end
      local entry = {key = d.key, value = d.value, tick = game.tick}
      storage.memory.prefs[d.key:lower()] = entry
      u.json_response({remembered = "pref", entry = entry})

    elseif d.type == "note" then
      if type(d.text) ~= "string" then u.error_response("note needs text"); return end
      local entry = {text = d.text, x = d.x, y = d.y, tick = game.tick}
      table.insert(storage.memory.notes, entry)
      while #storage.memory.notes > MAX_NOTES do table.remove(storage.memory.notes, 1) end
      u.json_response({remembered = "note", entry = entry, total_notes = #storage.memory.notes})

    else
      u.error_response("unknown type: " .. tostring(d.type))
    end
  end)
end)

-- ---- Recall: query memory. "fac_memory_recall <type> [substring]" ----
-- type: location | pref | note | all. Optional substring filters name/kind/key/value/text.
commands.add_command("fac_memory_recall", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local args = u.parse_args("^(%S+)%s*(.*)$", cmd.parameter)
    local typ = (args[1] ~= "" and args[1]) or "all"
    local q = (args[2] and args[2] ~= "") and args[2]:lower() or nil
    local function hit(...)
      if not q then return true end
      for _, v in ipairs({...}) do
        if type(v) == "string" and v:lower():find(q, 1, true) then return true end
      end
      return false
    end

    local out = {}
    if typ == "location" or typ == "all" then
      local locs = {}
      for _, e in pairs(storage.memory.locations) do
        if hit(e.name, e.kind, e.note) then locs[#locs + 1] = e end
      end
      out.locations = locs
    end
    if typ == "pref" or typ == "all" then
      local prefs = {}
      for _, e in pairs(storage.memory.prefs) do
        if hit(e.key, e.value) then prefs[#prefs + 1] = e end
      end
      out.prefs = prefs
    end
    if typ == "note" or typ == "all" then
      local notes = {}
      for _, e in ipairs(storage.memory.notes) do
        if hit(e.text) then notes[#notes + 1] = e end
      end
      out.notes = notes
    end
    u.json_response(out)
  end)
end)

-- ---- Forget: "fac_memory_forget <type> <name/key/index>" ----
commands.add_command("fac_memory_forget", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local args = u.parse_args("^(%S+)%s+(.+)$", cmd.parameter)
    local typ, key = args[1], args[2]
    if not typ or not key then u.error_response("Usage: <location|pref|note> <name/key/index>"); return end
    if typ == "location" then
      local k = key:lower()
      local existed = storage.memory.locations[k] ~= nil
      storage.memory.locations[k] = nil
      clear_location_tag(k)
      u.json_response({forgot = existed, type = typ, key = key})
    elseif typ == "pref" then
      local k = key:lower()
      local existed = storage.memory.prefs[k] ~= nil
      storage.memory.prefs[k] = nil
      u.json_response({forgot = existed, type = typ, key = key})
    elseif typ == "note" then
      local idx = tonumber(key)
      if idx and storage.memory.notes[idx] then
        table.remove(storage.memory.notes, idx)
        u.json_response({forgot = true, type = typ, index = idx})
      else
        u.json_response({forgot = false, reason = "no note at index " .. tostring(key)})
      end
    else
      u.error_response("unknown type: " .. tostring(typ))
    end
  end)
end)

-- ---- List: full dump (counts + entries) — good as a session-start "what I know". ----
commands.add_command("fac_memory_list", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local locs, prefs = {}, {}
    for _, e in pairs(storage.memory.locations) do locs[#locs + 1] = e end
    for _, e in pairs(storage.memory.prefs) do prefs[#prefs + 1] = e end
    u.json_response({
      locations = locs, prefs = prefs, notes = storage.memory.notes,
      counts = {locations = #locs, prefs = #prefs, notes = #storage.memory.notes},
    })
  end)
end)

-- ---- Go to a remembered place: "fac_memory_goto <companionId> <name>" ----
commands.add_command("fac_memory_goto", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local args = u.parse_args("^(%S+)%s+(.+)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local name = args[2]
    if not name then u.error_response("Usage: <companionId> <location name>"); return end
    local e = storage.memory.locations[name:lower()]
    if not e then u.json_response({id = id, error = "no remembered location named '" .. name .. "'"}); return end
    nav.go_to(id, {x = e.x, y = e.y}, {radius = 2})
    u.json_response({id = id, going_to = e.name, at = {x = e.x, y = e.y}, kind = e.kind})
  end)
end)

-- ---- Auto-survey + remember resource patches (Pillar III: the buddy learns the map).
-- Scan resources in radius, group by type, and remember ONE location per type at its
-- centroid (kind="ore", with a map tag) — so the companion builds up knowledge of where
-- the ores are, on its own. "fac_survey_remember <companionId> [radius]"
commands.add_command("fac_survey_remember", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local args = u.parse_args("^(%S+)%s*(%d*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local radius = tonumber(args[2]) or 100
    local e = c.entity
    local area = {{e.position.x - radius, e.position.y - radius}, {e.position.x + radius, e.position.y + radius}}
    local agg = {}
    for _, r in ipairs(e.surface.find_entities_filtered{area = area, type = "resource"}) do
      local a = agg[r.name] or {sx = 0, sy = 0, n = 0, amount = 0}
      a.sx = a.sx + r.position.x; a.sy = a.sy + r.position.y; a.n = a.n + 1; a.amount = a.amount + (r.amount or 0)
      agg[r.name] = a
    end
    local saved = {}
    for name, a in pairs(agg) do
      local lname = name .. " patch"
      local key = lname:lower()
      local entry = loc_entry(lname, "ore", a.sx / a.n, a.sy / a.n, "~" .. a.amount .. " (auto-surveyed)")
      storage.memory.locations[key] = entry
      set_location_tag(key, entry, id)
      saved[#saved + 1] = {name = lname, x = entry.x, y = entry.y, amount = a.amount}
    end
    u.json_response({id = id, radius = radius, remembered = saved, count = #saved})
  end)
end)

-- ---- Nearest remembered location by kind/name to the companion (the buddy uses what
-- it knows). "fac_memory_nearest <companionId> [kind|substring]"
commands.add_command("fac_memory_nearest", nil, function(cmd)
  u.safe_command(function()
    M.init()
    local args = u.parse_args("^(%S+)%s*(.*)$", cmd.parameter)
    local id, c = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local q = (args[2] and args[2] ~= "") and args[2]:lower() or nil
    local pos = c.entity.position
    local best, bd = nil, math.huge
    for _, ent in pairs(storage.memory.locations) do
      local match = not q or (ent.name:lower():find(q, 1, true) or (ent.kind and ent.kind:lower():find(q, 1, true)))
      if match then
        local d = math.sqrt((ent.x - pos.x) ^ 2 + (ent.y - pos.y) ^ 2)
        if d < bd then bd, best = d, ent end
      end
    end
    if not best then u.json_response({id = id, error = "no remembered location matching '" .. tostring(q) .. "'"}); return end
    u.json_response({id = id, nearest = best, distance = math.floor(bd)})
  end)
end)

return M
