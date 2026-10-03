-- Execute the real controller against a stateful 0.55-shaped compositor double.
-- This validates dispatch selection and event/focus interactions without a GPU.
local source = assert(arg[1], "pass the desktop-controls.lua path")
local count = 0
local function eq(actual, expected, description)
  assert(actual == expected, (description or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function fixture(paired)
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
  s.control.setup(paired)
  if paired then
    s:emit("hyprland.start")
    s:run_timers(100)
  end
  return s
end
local function test(name, fn)
  fn()
  count = count + 1
  print("ok " .. count .. " - " .. name)
end

test("all nine logical workspaces pair from either monitor and preserve cursor", function()
  for _, side in ipairs({ "studio", "laptop" }) do
    for n = 1, 9 do
      local s = fixture(true)
      s.active_monitor = s[side]
      s.control.workspace(n)
      eq(s.studio.active_workspace.id, n)
      eq(s.laptop.active_workspace.id, n + 10)
      eq(s.active_monitor, s[side])
      eq(s.cursor.x, 42); eq(s.cursor.y, 87)
      assert(#s.calls <= 3, "recursive workspace events must not loop")
    end
  end
end)

test("bar click synchronizes peer and returns focus to clicked monitor", function()
  local s = fixture(true)
  s:activate(14)
  eq(#s.calls, 0, "workspace event synchronization must be deferred")
  s:run_timers(1)
  eq(s.studio.active_workspace.id, 4); eq(s.laptop.active_workspace.id, 14)
  eq(s.active_monitor, s.laptop)
  eq(#s.calls, 3)
end)

test("pair sync explicitly restores an already-active empty origin monitor", function()
  local s = fixture(true)
  local peer_window = s:add_window(14)
  s.window = nil
  s.active_monitor = s.studio
  s.studio.active_workspace = s.workspaces[4]
  s.control.workspace(4)
  eq(s.studio.active_workspace.id, 4); eq(s.laptop.active_workspace.id, 14)
  eq(s.active_monitor, s.studio)
  eq(s.window, nil, "keyboard focus must not remain on the peer window")
  eq(s.calls[2].args.monitor, s.studio.name)
  assert(peer_window ~= s.window)
end)

test("already paired activation does not steal a window's focus", function()
  local s = fixture(true)
  local window = s:add_window(1)
  s:emit("workspace.active", s.workspaces[1])
  s:run_timers(1)
  eq(#s.calls, 0); eq(s.window, window)
end)

test("numbered window move follows same monitor bank and synchronizes both", function()
  for _, id in ipairs({ 1, 11 }) do
    local s = fixture(true)
    local window = s:add_window(id)
    s.control.move_to_workspace(8)
    eq(window.workspace.id, id == 1 and 8 or 18)
    eq(s.studio.active_workspace.id, 8); eq(s.laptop.active_workspace.id, 18)
    eq(s.window, window); eq(s.active_monitor, window.monitor)
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

test("hotplug resynchronizes after persistent relocation, preserving active number", function()
  local s = fixture(true)
  s.monitors = { s.laptop }; s.active_monitor = s.laptop
  s.control.workspace(7)
  s.monitors = { s.studio, s.laptop }
  s:emit("monitor.added", s.studio)
  eq(s.studio.active_workspace.id, 1, "must defer past persistent creation")
  s:run_timers()
  eq(s.studio.active_workspace.id, 7); eq(s.laptop.active_workspace.id, 17)
  eq(s.active_monitor, s.laptop)
end)

test("foreign and special workspaces are left alone", function()
  local s = fixture(true)
  s:emit("workspace.active", { id = 42, monitor = s.studio })
  s:emit("workspace.active", { id = -99, special = true, monitor = s.studio })
  s:emit("workspace.active", { id = 3, monitor = s.laptop }) -- migrated bank
  eq(#s.calls, 0)
  s.special = { id = -99, special = true }
  s:emit("config.reloaded"); s:run_timers(); eq(#s.calls, 0)
end)

test("automatic reconciliation preserves a special open on the nonfocused peer", function()
  local s = fixture(true)
  s.active_monitor = s.laptop
  s.laptop.active_workspace = s.workspaces[11]
  s.studio.active_workspace = s.workspaces[2]
  s.studio.active_special_workspace = { id = -99, special = true }
  s:emit("config.reloaded")
  s:run_timers(100)
  eq(#s.calls, 0)
  assert(s.studio.active_special_workspace, "peer special must remain open")
end)

test("config verification without an active monitor does not create a timer", function()
  local s = fixture(true)
  s.monitors = {}
  s.active_monitor = nil
  s:emit("config.reloaded")
  eq(#s.timers, 0)
  eq(#s.calls, 0)
end)

test("disconnect migration events wait for removal and restore the surviving bank", function()
  local s = fixture(true)
  s.control.workspace(7)
  local stable_calls = #s.calls
  local laptop_window = s:add_window(17)
  s.active_monitor = s.studio
  s.studio.active_workspace = s.workspaces[7]

  -- onDisconnect changes the disabled monitor's workspace while it is still in
  -- get_monitors(), then migrates workspaces, and only then erases the monitor.
  s.studio.active_workspace = s.workspaces[2]
  s:emit("workspace.active", s.workspaces[2])
  eq(#s.calls, stable_calls, "migration must not synchronously focus either output")
  s.workspaces[2].monitor = s.laptop
  s.active_monitor = s.laptop
  s.laptop.active_workspace = s.workspaces[2]
  s.window = laptop_window
  s:emit("workspace.active", s.workspaces[2])
  s.monitors = { s.laptop }
  s:emit("monitor.removed", s.studio)
  s:run_timers(1)
  eq(#s.calls, stable_calls, "stale migration callbacks must be invalidated")
  s:run_timers(100)
  eq(s.laptop.active_workspace.id, 17)
  eq(s.window, laptop_window, "focused window on the stable bank must survive")
  eq(s.cursor.x, 42); eq(s.cursor.y, 87)
end)

test("newer bar activation invalidates an older deferred workspace event", function()
  local s = fixture(true)
  s:activate(14)
  s:activate(3)
  s:run_timers(1)
  eq(s.studio.active_workspace.id, 3); eq(s.laptop.active_workspace.id, 13)
  eq(s.active_monitor, s.studio)
  eq(#s.calls, 3, "only the newest activation may synchronize")
end)

test("reattach identifies StudioDisplay by description despite connector and order changes", function()
  local s = fixture(true)
  s.monitors = { s.laptop }; s.active_monitor = s.laptop
  s.control.workspace(6)
  local replacement = {
    name = "DP-42", description = "Apple Computer Inc StudioDisplay Different serial",
    active_workspace = s.workspaces[1],
  }
  for n = 1, 9 do s.workspaces[n].monitor = replacement end
  s.monitors = { s.laptop, replacement }
  s:emit("monitor.added", replacement)
  s:run_timers(100)
  eq(replacement.active_workspace.id, 6); eq(s.laptop.active_workspace.id, 16)
  eq(s.active_monitor, s.laptop)
end)

test("failed synchronization releases recursion guard", function()
  local s = fixture(true)
  s.fail_next = true
  local ok = pcall(s.control.workspace, 2)
  eq(ok, false)
  s.control.workspace(3)
  eq(s.studio.active_workspace.id, 3); eq(s.laptop.active_workspace.id, 13)
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
  eq(#s.events["workspace.active"], 1)
end)

print("1.." .. count)
