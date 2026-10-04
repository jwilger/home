-- Execute the real controller against a stateful 0.55-shaped compositor double.
-- This validates dispatch selection and event/focus interactions without a GPU.
local source = assert(arg[1], "pass the desktop-controls.lua path")
local count = 0
local function eq(actual, expected, description)
  assert(actual == expected, (description or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function fixture(per_monitor)
  local s = { calls = {}, events = {}, timers = {}, cursor = { x = 42, y = 87 }, windows = {} }
  s.studio = { name = "DP-7", description = "Apple Computer Inc StudioDisplay Serial", focused = true }
  s.laptop = { name = "eDP-1", description = "Built-in display" }
  s.monitors = { s.studio, s.laptop }
  s.active_monitor = s.studio
  s.workspaces = {}
  for n = 1, 9 do
    s.workspaces[n] = { id = n, name = tostring(n), monitor = s.studio, tiled_layout = "scrolling" }
    s.workspaces[n + 10] = { id = n + 10, name = n .. "-laptop", monitor = s.laptop, tiled_layout = "scrolling" }
  end
  s.studio.active_workspace = s.workspaces[1]
  s.laptop.active_workspace = s.workspaces[11]
  local function action(kind, args) return { kind = kind, args = args } end
  local function emit(event, value)
    for _, callback in ipairs(s.events[event] or {}) do callback(value) end
  end
  local function focus(id)
    local workspace = assert(s.workspaces[tonumber(id)], "unknown workspace " .. tostring(id))
    local monitor = workspace.monitor
    if monitor.active_workspace == workspace then return end
    s.active_monitor = monitor
    monitor.active_workspace = workspace
    s.cursor = { x = monitor == s.studio and 2000 or 500, y = 500 }
    s.window = workspace.last_window
    emit("workspace.active", workspace)
  end
  local function focus_monitor(name)
    local monitor
    for _, candidate in ipairs(s.monitors) do if candidate.name == name then monitor = candidate end end
    assert(monitor, "unknown monitor " .. tostring(name))
    s.active_monitor = monitor
    s.cursor = { x = monitor == s.studio and 2000 or 500, y = 500 }
    s.window = monitor.active_workspace.last_window
  end
  _G.hl = {
    dsp = {
      focus = function(args) return action("focus", args) end,
      layout = function(args) return action("layout", args) end,
      cursor = { move = function(args) return action("cursor", args) end },
      window = { move = function(args) return action("move", args) end },
    },
    dispatch = function(a)
      s.calls[#s.calls + 1] = a
      if s.fail_next then s.fail_next = false; error("fixture dispatch failure") end
      if a.kind == "focus" and a.args.workspace then focus(a.args.workspace)
      elseif a.kind == "focus" and a.args.monitor then focus_monitor(a.args.monitor)
      elseif a.kind == "cursor" then s.cursor = a.args
      elseif a.kind == "move" and a.args.workspace then
        local window = s.window
        window.workspace = s.workspaces[tonumber(a.args.workspace)]
        window.monitor = window.workspace.monitor
        window.workspace.last_window = window
        if a.args.follow then
          focus(a.args.workspace)
          s.active_monitor = window.monitor
          s.window = window
        end
      elseif a.kind == "layout" and a.args:match("^focus ") and s.next_window then
        s.window = s.next_window
      end
    end,
    get_monitors = function() return s.monitors end,
    get_active_monitor = function() return s.active_monitor end,
    get_active_workspace = function() return s.active_monitor and s.active_monitor.active_workspace end,
    get_active_special_workspace = function()
      return s.special or (s.active_monitor and s.active_monitor.active_special_workspace)
    end,
    get_active_window = function() return s.window end,
    get_workspace_windows = function(workspace)
      local windows = {}
      for _, window in ipairs(s.windows) do if window.workspace == workspace then windows[#windows + 1] = window end end
      return windows
    end,
    get_cursor_pos = function() return s.cursor end,
    on = function(event, callback)
      s.events[event] = s.events[event] or {}
      table.insert(s.events[event], callback)
    end,
    timer = function(callback, options)
      eq(options.type, "oneshot")
      assert(options.timeout == 1 or options.timeout == 100, "unexpected timer delay")
      table.insert(s.timers, { callback = callback, timeout = options.timeout })
    end,
  }
  function s:add_window(id, index, floating)
    local workspace = self.workspaces[id]
    local window = { workspace = workspace, monitor = workspace.monitor, floating = floating or false }
    if not floating then window.layout = { column = { index = index or 0 } } end
    table.insert(self.windows, window)
    self.window = window
    self.active_monitor = window.monitor
    workspace.last_window = window
    return window
  end
  function s:activate(id) focus(id) end
  function s:emit(event, value) emit(event, value) end
  function s:run_timers(timeout)
    local pending = {}
    local ready = {}
    for _, timer in ipairs(self.timers) do
      if not timeout or timer.timeout == timeout then ready[#ready + 1] = timer
      else pending[#pending + 1] = timer end
    end
    self.timers = pending
    for _, timer in ipairs(ready) do timer.callback() end
  end
  s.control = dofile(source)
  s.control.setup(per_monitor)
  return s
end
local function test(name, fn)
  fn()
  count = count + 1
  print("ok " .. count .. " - " .. name)
end

test("numbered workspace selection stays on the invoking monitor bank", function()
  for _, side in ipairs({ "studio", "laptop" }) do
    for n = 1, 9 do
      local s = fixture(true)
      s.active_monitor = s[side]
      s.control.workspace(n)
      eq(s.studio.active_workspace.id, side == "studio" and n or 1)
      eq(s.laptop.active_workspace.id, side == "laptop" and n + 10 or 11)
      eq(s.active_monitor, s[side])
      eq(#s.calls, n == 1 and 0 or 1)
    end
  end
end)

test("workspace events do not install automatic synchronization or timers", function()
  local s = fixture(true)
  s:activate(14)
  eq(s.studio.active_workspace.id, 1)
  eq(s.laptop.active_workspace.id, 14)
  eq(s.active_monitor, s.laptop)
  eq(#s.calls, 0)
  eq(#s.timers, 0)
end)

test("already-active workspace selection does not touch the peer monitor", function()
  local s = fixture(true)
  s.active_monitor = s.studio
  s.studio.active_workspace = s.workspaces[4]
  s.control.workspace(4)
  eq(s.studio.active_workspace.id, 4); eq(s.laptop.active_workspace.id, 11)
  eq(s.active_monitor, s.studio)
  eq(#s.calls, 0)
end)

test("workspace selection preserves the focused window on its monitor", function()
  local s = fixture(true)
  local window = s:add_window(1)
  s.control.workspace(1)
  eq(#s.calls, 0); eq(s.window, window)
end)

test("numbered window move stays in the window's monitor bank", function()
  for _, id in ipairs({ 1, 11 }) do
    local s = fixture(true)
    local window = s:add_window(id)
    s.control.move_to_workspace(8)
    eq(window.workspace.id, id == 1 and 8 or 18)
    eq(s.studio.active_workspace.id, id == 1 and 8 or 1)
    eq(s.laptop.active_workspace.id, id == 11 and 18 or 11)
    eq(s.window, window); eq(s.active_monitor, window.monitor)
    eq(#s.calls, 1)
  end
end)

test("monitor transfer targets matching bank and follows the moved window", function()
  local s = fixture(true)
  s.control.workspace(5)
  local window = s:add_window(5)
  s.control.move_to_monitor("l")
  eq(window.workspace.id, 15); eq(s.window, window); eq(s.active_monitor, s.laptop)
  s.control.move_to_monitor("r")
  eq(window.workspace.id, 5); eq(s.window, window); eq(s.active_monitor, s.studio)
  local calls = #s.calls
  s.control.move_to_monitor("r")
  eq(#s.calls, calls, "no destination to the right of StudioDisplay")
end)

test("undocked laptop uses its bank without dispatching to missing monitor", function()
  local s = fixture(true)
  s.monitors = { s.laptop }; s.active_monitor = s.laptop
  s.control.workspace(7)
  eq(s.laptop.active_workspace.id, 17); eq(#s.calls, 1)
  s:add_window(17); s.control.move_to_monitor("r"); eq(#s.calls, 1)
end)

test("external-only and Gregor retain ordinary numeric shortcuts", function()
  local s = fixture(true)
  s.monitors = { s.studio }; s.control.workspace(6)
  eq(s.studio.active_workspace.id, 6); eq(#s.calls, 1)
  s = fixture(false)
  s.control.workspace(8); eq(s.studio.active_workspace.id, 8)
  eq(next(s.events), nil)
  s:add_window(8); s.control.move_to_monitor("l")
  eq(s.calls[#s.calls].args.monitor, "l")
end)

test("setup only selects a bank and registers no automatic lifecycle handlers", function()
  local s = fixture(true)
  eq(next(s.events), nil)
  eq(#s.timers, 0)
end)

test("setup without per-monitor banks keeps ordinary numeric workspaces", function()
  local s = fixture(false)
  s.control.workspace(8)
  eq(s.studio.active_workspace.id, 8)
  eq(#s.timers, 0)
  eq(next(s.events), nil)
end)

test("dwindle and master navigate and move natively without scrolling dispatch", function()
  for _, layout in ipairs({ "dwindle", "master" }) do
    for _, direction in ipairs({ "l", "r", "u", "d" }) do
      local s = fixture(true); s:add_window(1); s.workspaces[1].tiled_layout = layout
      s.control.focus(direction); s.control.move(direction)
      eq(s.calls[1].kind, "focus"); eq(s.calls[1].args.direction, direction)
      eq(s.calls[2].kind, "move"); eq(s.calls[2].args.direction, direction)
    end
  end
end)

test("monocle navigates its overlapping windows with cycle commands", function()
  for direction, command in pairs({ l = "cycleprev", u = "cycleprev", r = "cyclenext", d = "cyclenext" }) do
    local s = fixture(true); s:add_window(1); s.workspaces[1].tiled_layout = "monocle"
    s.control.focus(direction); eq(s.calls[1].kind, "layout"); eq(s.calls[1].args, command)
    s.control.move(direction); eq(s.calls[2].kind, "move")
  end
end)

test("scrolling focuses columns and falls back to monitor navigation at an edge", function()
  local s = fixture(true); local first = s:add_window(1, 0); local next_window = s:add_window(1, 1)
  s.window = first; s.next_window = next_window
  s.control.focus("r"); eq(#s.calls, 1); eq(s.calls[1].args, "focus r")
  s.next_window = nil
  s.control.focus("r"); eq(#s.calls, 3); eq(s.calls[3].kind, "focus"); eq(s.calls[3].args.direction, "r")
end)

test("scrolling swaps existing adjacent columns but uses native movement at edges", function()
  local s = fixture(true); local first = s:add_window(1, 0); s:add_window(1, 1); s.window = first
  s.control.move("r"); eq(s.calls[1].kind, "layout"); eq(s.calls[1].args, "swapcol r")
  s.control.move("l"); eq(s.calls[2].kind, "move"); eq(s.calls[2].args.direction, "l")
  s = fixture(true); s:add_window(1, 0); s.control.move("r"); eq(s.calls[1].kind, "move")
end)

test("scrolling-only fit and resize never dispatch in another layout", function()
  for _, layout in ipairs({ "dwindle", "master", "monocle", "scrolling" }) do
    local s = fixture(true); s:add_window(1); s.workspaces[1].tiled_layout = layout
    for _, command in ipairs({ "fit active", "colresize +conf", "colresize -0.1", "colresize +0.1" }) do s.control.scrolling(command) end
    eq(#s.calls, layout == "scrolling" and 4 or 0)
  end
end)

test("floating and empty workspaces avoid tiled-only commands", function()
  local s = fixture(true)
  s.control.focus("l"); eq(s.calls[1].kind, "focus")
  s.calls = {}; s.control.move("l"); s.control.scrolling("fit active"); s.control.move_to_workspace(2); s.control.move_to_monitor("l")
  eq(#s.calls, 0)
  s:add_window(1, nil, true)
  s.control.focus("l"); s.control.move("r"); s.control.scrolling("fit active")
  eq(#s.calls, 2); eq(s.calls[1].kind, "focus"); eq(s.calls[2].kind, "move")
end)

test("setup is idempotent", function()
  local s = fixture(true); s.control.setup(true)
  eq(next(s.events), nil)
end)

print("1.." .. count)
