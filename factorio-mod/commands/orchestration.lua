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

-- ---- Plans (Phase 5b: persistent task tree for goal decomposition) ----
-- The LLM decomposes a high-level goal into ordered steps and stores them here so
-- progress is observable and survives saves. Execution stays LLM-driven.

function M.plan_create(goal, steps)
  storage.plans = storage.plans or {}
  local pid = storage.plan_next_id or 1
  storage.plan_next_id = pid + 1
  local s = {}
  for i, desc in ipairs(steps or {}) do s[i] = {desc = desc, status = "pending"} end
  if s[1] then s[1].status = "active" end
  storage.plans[pid] = {id = pid, goal = goal, steps = s, current = 1, created = game.tick}
  return storage.plans[pid]
end

function M.plan_step_done(pid)
  local p = storage.plans and storage.plans[pid]
  if not p then return nil end
  if p.steps[p.current] then p.steps[p.current].status = "done" end
  p.current = p.current + 1
  if p.steps[p.current] then p.steps[p.current].status = "active" else p.done = true end
  return p
end

commands.add_command("fac_plan_create", nil, function(cmd)
  u.safe_command(function()
    local ok, data = pcall(helpers.json_to_table, cmd.parameter or "")
    if not ok or type(data) ~= "table" or not data.goal then
      u.error_response('Usage: JSON {"goal":"...","steps":["s1","s2"]}'); return
    end
    u.json_response({created = true, plan = M.plan_create(data.goal, data.steps)})
  end)
end)

commands.add_command("fac_plan_status", nil, function(cmd)
  u.safe_command(function()
    local pid = tonumber(cmd.parameter)
    if not pid or pid < 1 then
      local out = {}
      for id, p in pairs(storage.plans or {}) do
        out[#out + 1] = {id = id, goal = p.goal, current = p.current, steps = #p.steps, done = p.done or false}
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

return M
