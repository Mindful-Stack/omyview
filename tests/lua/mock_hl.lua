-- In-memory stand-in for Hyprland's `hl` table, just enough for the chunks logic.js builds.
-- Dispatches mutate window state and are logged. Like Hyprland's, `hl.dispatch` never raises:
-- it returns { ok = true } or, when `hl.__fail_on = "window.float"` names the dispatcher (every
-- time, or only its `hl.__fail_nth` occurrence), { ok = false, error = "..." } — the chunk's own
-- run() guard is what turns that into the failure path. Geometry never re-lays out (no dwindle here) and focus
-- is a constant: tests assert dispatch order and end state, never geometry.
-- A new dispatcher used by a chunk must be added to `hl.dsp` AND applied in `hl.dispatch`;
-- never stub it as a no-op, or "ends tiled"-style checks become vacuous.
local M = {}

function M.new(opts)
  opts = opts or {}
  local hl = { __log = {}, __notifications = {}, __printed = {}, __fail_on = nil, __fail_nth = nil,
    __seen = {}, __config = {
    ["general.layout"] = opts.layout or "dwindle",
    ["dwindle.smart_split"] = false, ["dwindle.use_active_for_splits"] = true } }
  hl.__windows = opts.windows or {}
  hl.__active_workspace = opts.active_workspace or { id = 1 }
  hl.__workspaces = opts.workspaces or {}
  hl.__active_window = opts.active_window or nil
  hl.__cursor = { x = 5, y = 6 }

  local function byAddress(sel)
    local a = sel:match("^address:(.+)$")
    return a and hl.__windows[a] or nil
  end
  function hl.get_window(sel) return byAddress(sel) end
  function hl.get_active_window() return hl.__active_window end
  function hl.get_cursor_pos() return { x = hl.__cursor.x, y = hl.__cursor.y } end
  function hl.get_active_workspace() return hl.__active_workspace end
  function hl.get_workspace(id)
    return hl.__workspaces[tostring(id)] or { fullscreen_window = nil, fullscreen_mode = 0 }
  end
  function hl.get_config(k)
    local v = hl.__config[k]
    if v == nil then return nil, "unknown config key '" .. k .. "'" end
    return v
  end
  function hl.config(t)
    for group, kv in pairs(t) do
      for k, v in pairs(kv) do hl.__config[group .. "." .. k] = v end
    end
  end
  hl.notification = { create = function(t) hl.__notifications[#hl.__notifications + 1] = t end }

  -- Typed dispatcher table: each entry returns a descriptor; hl.dispatch applies it.
  local function d(name) return function(args) return { name = name, args = args } end end
  hl.dsp = {
    focus = d("focus"),
    cursor = { move = d("cursor.move") },
    window = { float = d("window.float"), move = d("window.move"), fullscreen = d("window.fullscreen") },
  }
  function hl.dispatch(desc)
    hl.__log[#hl.__log + 1] = desc
    hl.__seen[desc.name] = (hl.__seen[desc.name] or 0) + 1
    if hl.__fail_on == desc.name and (hl.__fail_nth == nil or hl.__fail_nth == hl.__seen[desc.name]) then
      return { ok = false, error = "injected failure in " .. desc.name, level = "error", code = "C_INVARG" }
    end
    local a = desc.args or {}
    local w = a.window and byAddress(a.window) or nil
    if desc.name == "window.float" and w then
      w.floating = not w.floating
    elseif desc.name == "window.move" and w then
      if a.workspace then w.workspace = { id = tonumber(a.workspace) } end
      if a.x and a.y then w.at = { x = tonumber(a.x), y = tonumber(a.y) } end
    elseif desc.name == "window.fullscreen" and w then
      -- Hyprland's toggle rule: asking for the mode the window has turns it off, otherwise switches.
      local want = (a.mode == "maximized") and 1 or 2
      w.fullscreen = (w.fullscreen == want) and 0 or want
    elseif desc.name == "cursor.move" then
      hl.__cursor = { x = a.x, y = a.y }
    end
    return { ok = true, pass_event = false }
  end
  return hl
end

-- Names of dispatches in order, e.g. { "window.float", "window.move", ... }.
function M.names(hl)
  local out = {}
  for i, e in ipairs(hl.__log) do out[i] = e.name end
  return out
end

return M
