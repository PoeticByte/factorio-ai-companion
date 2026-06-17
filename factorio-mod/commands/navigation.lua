-- AI Companion - Navigation (Phase 1: real pathfinding)
-- The engine's unit pathfinder does the hard part (obstacle-aware A*) via
-- surface.request_path; results arrive async on on_script_path_request_finished.
-- Characters have NO autopilot, so we still drive walking_state manually -- but
-- along the engine-computed waypoints instead of a naive straight line.
local u = require("commands.init")

local M = {}

-- nav.tick runs once per control on_nth_tick(5), i.e. every 5 game ticks.
local ARRIVE_TOLERANCE = 1.2   -- distance to consider a waypoint reached
local GOAL_TOLERANCE   = 1.0   -- how close request_path must get to the goal (radius)
local STUCK_CHECKS     = 24    -- nav.tick calls of no progress -> repath (~2s)
local STUCK_DIST       = 0.4   -- min progress between checks to count as "moving"
local REPATH_TICKS     = 60    -- follow: reissue path at most this often (~1s)
local FOLLOW_STOP_DIST = 4     -- follow: stop walking once this close to target

function M.init()
  storage.walking_queues = storage.walking_queues or {}
  storage.path_requests = storage.path_requests or {}   -- request_id -> {cid, goal}
  storage.nav_last = storage.nav_last or {}             -- cid -> {result, goal, tick}
end

local function set_last(cid, result, goal)
  storage.nav_last = storage.nav_last or {}
  storage.nav_last[cid] = {result = result, goal = goal, tick = game.tick}
end
M.set_last = set_last

-- Issue an async pathfinding request toward goal. opts.follow_player keeps the
-- queue alive after arrival; opts.radius overrides goal tolerance.
function M.go_to(cid, goal, opts)
  local c = u.get_companion(cid)
  if not c then return {error = "Companion not found"} end
  opts = opts or {}
  local e = c.entity
  local proto = e.prototype

  -- Already there: skip the pathfinder.
  if not opts.follow_player and u.distance(e.position, goal) < (opts.radius or GOAL_TOLERANCE) then
    e.walking_state = {walking = false}
    storage.walking_queues[cid] = nil
    set_last(cid, "arrived", {x = goal.x, y = goal.y})
    return {arrived = true, goal = {x = goal.x, y = goal.y}}
  end

  local req_id = e.surface.request_path{
    bounding_box = proto.collision_box,   -- MUST be the centered prototype box, not entity.bounding_box
    collision_mask = proto.collision_mask,
    start = e.position,
    goal = goal,
    force = e.force,
    radius = opts.radius or GOAL_TOLERANCE,
    pathfind_flags = {cache = false, low_priority = true},
    can_open_gates = true,
    entity_to_ignore = e,   -- ignore the companion's own body, else the START tile reads as blocked
  }

  storage.path_requests[req_id] = {cid = cid, goal = {x = goal.x, y = goal.y}}

  -- Mark intent immediately (status shows "walking" even before the path arrives).
  -- Keep any existing waypoints so a re-path while moving doesn't stutter.
  local q = storage.walking_queues[cid] or {}
  q.goal = {x = goal.x, y = goal.y}
  q.follow_player = opts.follow_player
  q.follow_dist = opts.radius or FOLLOW_STOP_DIST
  q.pending = true
  q.last_repath_tick = game.tick
  storage.walking_queues[cid] = q
  set_last(cid, "walking", q.goal)

  return {requested = true, request_id = req_id, goal = q.goal}
end

-- Start following a player (re-paths periodically as the player moves).
function M.follow(cid, player_name)
  if not game.get_player(player_name) then return {error = "Player not found"} end
  storage.walking_queues[cid] = {follow_player = player_name, follow_dist = FOLLOW_STOP_DIST}
  set_last(cid, "walking", nil)
  return {following = player_name}
end

function M.stop(cid)
  storage.walking_queues[cid] = nil
  local c = u.get_companion(cid)
  if c then c.entity.walking_state = {walking = false} end
  set_last(cid, "stopped", nil)
end

-- Event: a request_path call finished. Match by id, store/refresh waypoints.
function M.on_path_finished(event)
  local req = storage.path_requests[event.id]
  if not req then return end
  storage.path_requests[event.id] = nil

  local cid = req.cid
  local q = storage.walking_queues[cid]
  if not q then return end           -- movement was cancelled meanwhile
  local c = u.get_companion(cid)
  if not c then storage.walking_queues[cid] = nil; return end

  q.pending = false

  if event.try_again_later then
    q.retry_at = game.tick + 15      -- pathfinder busy, retry shortly
    return
  end

  if not event.path then
    -- No path found.
    if q.follow_player then
      q.waypoints = nil
      q.retry_at = game.tick + 30    -- keep trying for a moving follow target
    else
      c.entity.walking_state = {walking = false}
      storage.walking_queues[cid] = nil
      set_last(cid, "unreachable", q.goal)
    end
    return
  end

  local wps = {}
  for _, wp in ipairs(event.path) do
    wps[#wps + 1] = {x = wp.position.x, y = wp.position.y}
  end
  q.waypoints = wps
  q.index = 1
  q.last_pos = {x = c.entity.position.x, y = c.entity.position.y}
  q.stuck_checks = 0
end

-- Per-tick follower. Returns true to remove the queue (done/invalid).
function M.tick(cid, q, c)
  local e = c.entity

  -- Following: keep goal synced to the player; stop when close; repath on interval.
  if q.follow_player then
    local p = game.get_player(q.follow_player)
    if not (p and p.valid and p.character) then return true end
    q.goal = {x = p.position.x, y = p.position.y}
    if u.distance(e.position, p.position) < (q.follow_dist or FOLLOW_STOP_DIST) then
      e.walking_state = {walking = false}
      q.waypoints = nil
      return false
    end
    if not q.pending and (not q.waypoints or (game.tick - (q.last_repath_tick or 0)) > REPATH_TICKS) then
      M.go_to(cid, q.goal, {follow_player = q.follow_player, radius = q.follow_dist})
      return false
    end
  end

  -- Deferred retry (try_again_later / unreachable-while-following).
  if q.retry_at and game.tick >= q.retry_at then
    q.retry_at = nil
    if q.goal then M.go_to(cid, q.goal, {follow_player = q.follow_player, radius = q.follow_dist}) end
    return false
  end

  -- No path yet: wait. (If a re-path is in flight but we still have old
  -- waypoints, keep following them so movement doesn't stutter.)
  if not q.waypoints then return false end

  local wp = q.waypoints[q.index]
  if not wp then
    -- Reached final waypoint.
    e.walking_state = {walking = false}
    if q.follow_player then q.waypoints = nil; return false end
    set_last(cid, "arrived", q.goal)
    return true
  end

  if u.distance(e.position, wp) < ARRIVE_TOLERANCE then
    q.index = q.index + 1
    return false
  end

  -- Stuck detection: no real progress for STUCK_CHECKS ticks -> repath.
  if q.last_pos and u.distance(e.position, q.last_pos) < STUCK_DIST then
    q.stuck_checks = (q.stuck_checks or 0) + 1
  else
    q.stuck_checks = 0
  end
  q.last_pos = {x = e.position.x, y = e.position.y}
  if (q.stuck_checks or 0) >= STUCK_CHECKS then
    q.stuck_checks = 0
    if q.goal and not q.pending then
      M.go_to(cid, q.goal, {follow_player = q.follow_player, radius = q.follow_dist})
    end
    return false
  end

  local dir = u.get_direction(e.position, wp)
  if dir then e.walking_state = {walking = true, direction = dir} end
  return false
end

return M
