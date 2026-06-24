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
end

local function loc_entry(name, kind, x, y, note)
  return {name = name, kind = kind or "custom", x = math.floor(x), y = math.floor(y),
          note = note, tick = game.tick}
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
      local entry = loc_entry(d.name, d.kind, x, y, d.note)
      storage.memory.locations[d.name:lower()] = entry
      u.json_response({remembered = "location", entry = entry})

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

return M
