-- AI Companion - Orchestration: task-board / reservations (Phase 5a)
-- Stops multiple companions claiming the same target. A reservation keys a thing
-- (ore-patch entity, ghost, nest area) to a companion; others skip claimed things.
-- Keys: "e:<unit_number>" for entities, "p:<x>,<y>" for positions/areas.
local u = require("commands.init")

local M = {}

local RESERVE_TTL = 18000   -- safety net: auto-expire a stale reservation after ~5 min

function M.init()
  storage.reservations = storage.reservations or {}
  storage.plans = storage.plans or {}
  storage.plan_next_id = storage.plan_next_id or 1
end

function M.entity_key(e)
  if not (e and e.valid) then return nil end
  if e.unit_number then return "e:" .. e.unit_number end
  -- resources / trees / cliffs have no unit_number — key them by tile instead
  return "p:" .. math.floor(e.position.x) .. "," .. math.floor(e.position.y)
end

function M.pos_key(pos)
  return "p:" .. math.floor(pos.x) .. "," .. math.floor(pos.y)
end

-- A reservation is live only while its holder companion exists, its target (if any)
-- is still valid, and it hasn't expired.
local function holder_valid(r)
  if not r then return false end
  if (game.tick - r.tick) > RESERVE_TTL then return false end
  if r.ent and not r.ent.valid then return false end
  local c = u.get_companion(r.cid)
  return (c and c.entity and c.entity.valid) and true or false
end
M.holder_valid = holder_valid

-- Claim `key` for cid. Returns true if it's ours (or newly claimed), false if another holds it.
function M.reserve(cid, key, kind, ent)
  if not key then return false end
  storage.reservations = storage.reservations or {}
  local r = storage.reservations[key]
  if r and r.cid ~= cid and holder_valid(r) then return false end
  storage.reservations[key] = {cid = cid, kind = kind or "target", tick = game.tick, ent = ent}
  return true
end

function M.is_reserved(key, except_cid)
  local r = key and storage.reservations and storage.reservations[key]
  if not r then return false end
  if r.cid == except_cid then return false end
  return holder_valid(r)
end

function M.release(cid, key)
  local r = key and storage.reservations and storage.reservations[key]
  if r and r.cid == cid then storage.reservations[key] = nil; return true end
  return false
end

function M.release_all(cid)
  if not storage.reservations then return 0 end
  local n = 0
  for k, r in pairs(storage.reservations) do
    if r.cid == cid then storage.reservations[k] = nil; n = n + 1 end
  end
  return n
end

-- Drop reservations whose holder/target is gone (called from the control tick).
function M.tick_reservations()
  if not storage.reservations then return end
  for k, r in pairs(storage.reservations) do
    if not holder_valid(r) then storage.reservations[k] = nil end
  end
end

function M.list()
  local out = {}
  if storage.reservations then
    for k, r in pairs(storage.reservations) do
      out[#out + 1] = {key = k, cid = r.cid, kind = r.kind}
    end
  end
  return out
end

-- ---- Commands ----

commands.add_command("fac_reserve", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local ok = M.reserve(id, args[2], "manual")
    u.json_response({id = id, key = args[2], reserved = ok})
  end)
end)

commands.add_command("fac_release", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)$", cmd.parameter)
    local id = u.find_companion(args[1])
    if not id then u.error_response("Companion not found"); return end
    local ok = M.release(id, args[2])
    u.json_response({id = id, key = args[2], released = ok})
  end)
end)

commands.add_command("fac_reservations", nil, function(cmd)
  u.safe_command(function()
    local list = M.list()
    u.json_response({reservations = list, count = #list})
  end)
end)

-- ---- Plans (Phase 5b + auto-execution) ----
-- The LLM decomposes a high-level goal into ordered steps. A step is either plain
-- text (manual: advance via plan_step_done) OR carries a structured `action` the
-- Lua executor runs itself. With auto=true, tick_plans claims a free companion for
-- the active step, reserves/starts the matching queue, watches it, and advances —
-- the colony self-drives. Progress is observable and survives saves.

-- queues.lua requires THIS module, so we can't require it back at load time
-- (a cycle) — and Factorio FORBIDS require() at runtime ("Require can't be used
-- outside of control.lua parsing"). So control.lua (which requires both) injects
-- them once via set_deps; the executor reads the stored refs.
local _queues, _nav
function M.set_deps(q, n) _queues, _nav = q, n end
local function deps() return _queues, _nav end

-- Normalize one incoming step: a string -> manual step; a table -> may carry an
-- action and explicit `deps` (1-based indices of steps it waits on).
local function norm_step(raw)
  if type(raw) == "string" then return {desc = raw, status = "pending"} end
  if type(raw) == "table" then
    local act = raw.action
    local desc = raw.desc or (act and act.type) or "step"
    return {desc = desc, status = "pending", action = act, deps = raw.deps}
  end
  return {desc = "step", status = "pending"}
end

function M.plan_create(goal, steps, auto)
  storage.plans = storage.plans or {}
  local pid = storage.plan_next_id or 1
  storage.plan_next_id = pid + 1
  local s = {}
  for i, raw in ipairs(steps or {}) do s[i] = norm_step(raw) end
  -- Resolve dependencies: explicit `deps` (filtered to valid in-range indices),
  -- else an implicit dependency on the previous step (sequential by default, so a
  -- plain ordered list still runs in order). deps = [] makes a step start at once.
  for i, st in ipairs(s) do
    local deps = {}
    if st.deps ~= nil then
      for _, di in ipairs(st.deps) do
        di = math.floor(tonumber(di) or 0)
        if di >= 1 and di <= #s and di ~= i then deps[#deps + 1] = di end
      end
    elseif i > 1 then
      deps = {i - 1}
    end
    st.deps = deps
  end
  storage.plans[pid] = {id = pid, goal = goal, steps = s, created = game.tick,
                        auto = auto and true or false}
  return storage.plans[pid]
end

-- Finish a step (status "done"|"failed"|"pending"), clearing its runtime fields.
local function finish_step(st, status, note)
  st.status = status or "done"
  st.note = note
  st.cid = nil; st.phase = nil; st.queue = nil; st.target = nil
end

-- Mark a plan done once every step is done/failed.
local function refresh_done(p)
  for _, st in ipairs(p.steps) do
    if st.status ~= "done" and st.status ~= "failed" then return end
  end
  p.done = true; p.auto = false
end

-- Manual advance (text steps): finish the earliest unfinished step.
function M.plan_step_done(pid)
  local p = storage.plans and storage.plans[pid]
  if not p then return nil end
  for _, st in ipairs(p.steps) do
    if st.status ~= "done" and st.status ~= "failed" then finish_step(st, "done"); break end
  end
  refresh_done(p)
  return p
end

-- ---- Auto-executor ----

-- Work queues that mean a companion is mid-task (mirrors queues.lua + nav).
local QUEUE_TABLES = {
  "harvest_queues", "craft_queues", "build_queues", "combat_queues", "ghost_build_queues",
  "haul_queues", "refuel_queues", "patrol_queues", "nest_clear_queues", "repair_queues",
  "walking_queues",
}
local function in_any_queue(cid)
  for _, name in ipairs(QUEUE_TABLES) do
    local t = storage[name]
    if t and t[cid] then return true end
  end
  return false
end

-- Already driving some plan's running step?
local function assigned_to_plan(cid)
  for _, p in pairs(storage.plans or {}) do
    for _, st in ipairs(p.steps or {}) do
      if st.status == "running" and st.cid == cid then return true end
    end
  end
  return false
end

-- Free = valid companion, not in a queue, not bound to a standing role, not on a plan.
local function is_free(cid)
  local c = u.get_companion(cid)
  if not c then return false end
  if in_any_queue(cid) then return false end
  if storage.roles and storage.roles[cid] then return false end
  if assigned_to_plan(cid) then return false end
  return true
end

-- An auto-assignable worker: free AND a robot (NOT an attached player character).
-- The autonomous executor never silently commandeers the protagonist — the player's
-- character only acts on a direct command or a step explicitly pinned to its id.
local function is_auto_worker(cid)
  local c = storage.companions[cid]
  return c and not c.is_player and is_free(cid)
end

local function pick_free_companion()
  for cid in pairs(storage.companions or {}) do
    if is_auto_worker(cid) then return cid end
  end
  return nil
end

-- Stamp a straight line of entity-ghosts (single machine = count 1). The ghost-build
-- queue then walks to each + revives it from the companion's inventory.
local function stamp_line(c, entity, x, y, dir, count)
  local proto = prototypes.entity[entity]
  if not proto then return nil, "unknown entity " .. tostring(entity) end
  local tw, th = proto.tile_width or 1, proto.tile_height or 1
  local dir_def = u.dir_map[dir or 0] or defines.direction.north
  local sx, sy = 0, 0
  if dir == 1 then sx = tw elseif dir == 3 then sx = -tw
  elseif dir == 2 then sy = th else sy = -th end
  local surf, force = c.entity.surface, c.entity.force
  local ghosts = {}
  for i = 0, math.max(1, count or 1) - 1 do
    local g = surf.create_entity{name = "entity-ghost", inner_name = entity,
      position = {x = x + sx * i, y = y + sy * i}, direction = dir_def, force = force}
    if g then ghosts[#ghosts + 1] = g end
  end
  return ghosts
end

-- Where a step's work happens (for nearest-worker allocation).
local function step_target_pos(st)
  local a = st.action
  if not a then return nil end
  if a.target then return a.target end
  if a.x and a.y then return {x = a.x, y = a.y} end
  if a.source then return a.source end
  return nil
end

-- Which crew specialty each action prefers (crew specialization, Pillar II).
local ACTION_SPECIALTY = {mine = "miner", build_line = "builder", craft = "builder", haul = "hauler"}

-- Can this companion actually DO the job right now (carries the materials / can craft)?
-- mine/haul/research need nothing carried.
local function can_do(cid, act)
  if not act then return true end
  if act.type == "build_line" then
    local c = u.get_companion(cid)
    return c and c.entity.get_main_inventory().get_item_count(act.entity) >= 1 or false
  elseif act.type == "craft" then
    local c = u.get_companion(cid)
    return c and c.entity.get_craftable_count(act.recipe) >= 1 or false
  end
  return true
end

-- Capability-aware negotiated allocation (Pillar II): among FREE companions, prefer in
-- tiers — (can-do AND matching specialty) > can-do > matching specialty > any — and
-- nearest within the chosen tier. So a build job goes to a companion that actually has
-- the materials (and ideally a builder), not just whoever's closest → fewer failed steps.
local function pick_worker(st)
  local tp = step_target_pos(st)
  local want = st.action and ACTION_SPECIALTY[st.action.type]
  local best, bd = {}, {math.huge, math.huge, math.huge, math.huge}
  for cid in pairs(storage.companions or {}) do
    if is_auto_worker(cid) then
      local c = u.get_companion(cid)
      local d = tp and u.distance(c.entity.position, tp) or 0
      local cap = can_do(cid, st.action)
      local spec = want and storage.companions[cid].specialty == want
      local tier = (cap and spec and 1) or (cap and 2) or (spec and 3) or 4
      if d < bd[tier] then bd[tier] = d; best[tier] = cid end
    end
  end
  return best[1] or best[2] or best[3] or best[4]
end

-- Research is force-level (no companion); set it, then watch until researched.
local function tick_research(st)
  local act = st.action
  local force = game.forces.player
  for _, c in pairs(storage.companions or {}) do
    if c.entity and c.entity.valid then force = c.entity.force; break end
  end
  if not force then return end
  local tech = force.technologies[act.tech]
  if not tech then finish_step(st, "failed", "unknown tech " .. tostring(act.tech)); return end
  if tech.researched then finish_step(st, "done", "researched"); return end
  if st.status ~= "running" then
    for _, pr in pairs(tech.prerequisites) do
      if not pr.researched then finish_step(st, "failed", "missing prereq " .. pr.name); return end
    end
    -- Space Age trigger techs aren't lab-researchable (they fire when you craft/build
    -- their trigger), so add_research can't queue them — say so clearly.
    if tech.prototype.research_trigger then
      finish_step(st, "failed", "trigger tech — research by crafting its trigger item, not via labs"); return
    end
    if force.add_research(act.tech) then st.status = "running"
    else finish_step(st, "failed", "add_research failed (not lab-researchable here)") end
  end
end

-- Begin a companion-driven action for a runnable step. Marks the step running
-- (so it won't be re-claimed) or fails it with a reason the LLM/user can read.
local function start_companion_action(st, cid)
  local queues, nav = deps()
  local c = u.get_companion(cid)
  local act = st.action
  local t = act.type
  st.cid = cid

  if t == "craft" then
    local r = queues.start_craft(cid, act.recipe, act.qty or 1)
    if r.error then finish_step(st, "failed", r.error)
    else st.status = "running"; st.queue = "craft_queues" end

  elseif t == "haul" then
    if not (act.item and act.source and act.dest) then finish_step(st, "failed", "haul needs item/source/dest"); return end
    local r = queues.start_haul(cid, act.item, act.source, act.dest, act.quota or 0)
    if r.error then finish_step(st, "failed", r.error)
    else st.status = "running"; st.queue = "haul_queues" end

  elseif t == "build_line" then
    local ghosts, err = stamp_line(c, act.entity, act.x, act.y, act.dir, act.count)
    if not ghosts or #ghosts == 0 then finish_step(st, "failed", err or "no ghosts placed"); return end
    local r = queues.start_ghost_build(cid, ghosts)
    if r.error then finish_step(st, "failed", r.error)
    else st.status = "running"; st.queue = "ghost_build_queues" end

  elseif t == "mine" then
    if not act.target then finish_step(st, "failed", "mine needs target {x,y}"); return end
    -- Walk to the patch first; the harvest queue itself doesn't path.
    st.status = "running"; st.queue = "harvest_queues"; st.phase = "travel"
    st.target = {x = act.target.x, y = act.target.y}
    nav.go_to(cid, st.target, {radius = 3})

  else
    finish_step(st, "failed", "unknown action type " .. tostring(t))
  end
end

-- Advance a running companion step: handle mine's travel pre-phase, else treat
-- "underlying queue gone" as the step being finished.
local function tick_running_step(st)
  local queues = deps()
  local cid = st.cid
  local c = u.get_companion(cid)
  if not c then finish_step(st, "failed", "companion lost"); return end

  if st.action.type == "mine" and st.phase == "travel" then
    if not (storage.walking_queues and storage.walking_queues[cid]) then
      if u.distance(c.entity.position, st.target) <= 5 then
        local r = queues.start_harvest(cid, st.target, st.action.qty or 50, st.action.resource)
        if r.error then finish_step(st, "failed", r.error); return end
        st.phase = "work"
      else
        finish_step(st, "failed", "patch unreachable")
      end
    end
    return
  end

  local qt = storage[st.queue]
  if not qt or not qt[cid] then finish_step(st, "done") end
end

-- A step is runnable once all its dependency steps are done. Returns
-- true (ready) | false (still waiting) | "depfail" (a dependency failed).
local function deps_done(p, st)
  for _, di in ipairs(st.deps or {}) do
    local d = p.steps[di]
    if d then
      if d.status == "failed" then return "depfail" end
      if d.status ~= "done" then return false end
    end
  end
  return true
end

-- Throttled from control.lua. Drives every auto plan as a dependency DAG: all
-- dependency-satisfied steps run in PARALLEL, each claimed by the nearest free
-- companion. This is what turns a plan into a crew effort (supply chains, division
-- of labor). ("active" is treated as "pending" for save-migration from v0.21.0.)
function M.tick_plans()
  for _, p in pairs(storage.plans or {}) do
    if p.auto and not p.done then
      for _, st in ipairs(p.steps) do
        local s = st.status
        if s == "running" then
          if st.action and st.action.type == "research" then tick_research(st)
          else tick_running_step(st) end
        elseif (s == "pending" or s == "active") and st.action then
          local rd = deps_done(p, st)
          if rd == "depfail" then
            finish_step(st, "failed", "dependency failed")
          elseif rd == true then
            if st.action.type == "research" then
              tick_research(st)                       -- no companion needed
            else
              local cid = st.action.cid
              if cid then
                if is_free(cid) then start_companion_action(st, cid) end   -- pinned: wait if busy
              else
                cid = pick_worker(st)
                if cid then start_companion_action(st, cid) end            -- else wait for a worker
              end
            end
          end
        end
      end
      refresh_done(p)
    end
  end
end

-- Turn auto-execution on/off. Off also halts every in-flight step + frees workers.
function M.plan_run(pid, on)
  local p = storage.plans and storage.plans[pid]
  if not p then return nil end
  if on then
    if not p.done then p.auto = true end
  else
    p.auto = false
    local queues = deps()
    for _, st in ipairs(p.steps) do
      if st.status == "running" and st.cid then
        local cid = st.cid
        if storage.harvest_queues and storage.harvest_queues[cid] then queues.stop_harvest(cid) end
        if storage.craft_queues and storage.craft_queues[cid] then queues.stop_craft(cid) end
        if storage.haul_queues and storage.haul_queues[cid] then queues.stop_haul(cid) end
        if storage.ghost_build_queues and storage.ghost_build_queues[cid] then queues.stop_ghost_build(cid) end
        if storage.walking_queues then storage.walking_queues[cid] = nil end
        M.release_all(cid)
        finish_step(st, "pending")   -- re-runnable when auto is turned back on
      end
    end
  end
  return p
end

commands.add_command("fac_plan_create", nil, function(cmd)
  u.safe_command(function()
    local ok, data = pcall(helpers.json_to_table, cmd.parameter or "")
    if not ok or type(data) ~= "table" or not data.goal then
      u.error_response('Usage: JSON {"goal":"...","auto":true,"steps":[{"desc":"..","action":{"type":"mine","target":{"x":0,"y":0},"resource":"iron-ore","qty":50}}]}'); return
    end
    u.json_response({created = true, plan = M.plan_create(data.goal, data.steps, data.auto)})
  end)
end)

commands.add_command("fac_plan_status", nil, function(cmd)
  u.safe_command(function()
    local pid = tonumber(cmd.parameter)
    if not pid or pid < 1 then
      local out = {}
      for id, p in pairs(storage.plans or {}) do
        local done = 0
        for _, st in ipairs(p.steps) do if st.status == "done" then done = done + 1 end end
        out[#out + 1] = {id = id, goal = p.goal, steps = #p.steps, done_steps = done,
                         auto = p.auto or false, done = p.done or false}
      end
      u.json_response({plans = out, count = #out}); return
    end
    local p = storage.plans and storage.plans[pid]
    if not p then u.error_response("Plan not found"); return end
    u.json_response({plan = p})
  end)
end)

commands.add_command("fac_plan_step_done", nil, function(cmd)
  u.safe_command(function()
    local pid = tonumber(cmd.parameter)
    if not pid then u.error_response("Need plan id"); return end
    local p = M.plan_step_done(pid)
    if not p then u.error_response("Plan not found"); return end
    u.json_response({plan = p})
  end)
end)

-- Toggle a plan's auto-execution: "fac_plan_run <pid> [on|off]" (default on).
commands.add_command("fac_plan_run", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%d+)%s*(%S*)$", cmd.parameter)
    local pid = tonumber(args[1])
    if not pid then u.error_response("Usage: <plan_id> [on|off]"); return end
    local a = args[2]
    local on = not (a == "off" or a == "false" or a == "0" or a == "stop")
    local p = M.plan_run(pid, on)
    if not p then u.error_response("Plan not found"); return end
    u.json_response({id = pid, auto = p.auto, plan = p})
  end)
end)

-- One-shot situational awareness for the orchestrator: companions, running plans,
-- standing roles, live reservations, and what the companion remembers. Pure reads.
commands.add_command("fac_overview", nil, function(cmd)
  u.safe_command(function()
    local comp_ids = {}
    for cid, c in pairs(storage.companions or {}) do
      if c.entity and c.entity.valid then comp_ids[#comp_ids + 1] = cid end
    end
    local plans = {}
    for id, p in pairs(storage.plans or {}) do
      local done = 0
      for _, st in ipairs(p.steps or {}) do if st.status == "done" then done = done + 1 end end
      plans[#plans + 1] = {id = id, goal = p.goal, steps = #(p.steps or {}), done_steps = done,
                           auto = p.auto or false, done = p.done or false}
    end
    local roles = {}
    for cid, r in pairs(storage.roles or {}) do roles[#roles + 1] = {cid = cid, role = r.role} end
    local nres = 0
    for _ in pairs(storage.reservations or {}) do nres = nres + 1 end
    local mem = storage.memory or {}
    local nloc, npref = 0, 0
    for _ in pairs(mem.locations or {}) do nloc = nloc + 1 end
    for _ in pairs(mem.prefs or {}) do npref = npref + 1 end
    u.json_response({
      companions = {count = #comp_ids, ids = comp_ids},
      plans = plans,
      roles = roles,
      reservations = nres,
      memory = {locations = nloc, prefs = npref, notes = #(mem.notes or {})},
    })
  end)
end)

return M
