local config_file, profile = assert(arg[1]), assert(arg[2])
local binds, rules, controls, config = {}, {}, {}, {}
local monitor_focus
local function noop() end
local function action() return noop end
local methods = { "workspace", "move_to_workspace", "move_to_monitor", "focus", "move", "scrolling", "setup" }
local controller = {}
for _, method in ipairs(methods) do
  controller[method] = function(value) controls[#controls + 1] = { method, value } end
end
package.preload["desktop-controls"] = function() return controller end
hl = {
  bind = function(keys, callback)
    assert(not binds[keys], "duplicate shortcut: " .. keys)
    assert(type(callback) == "function", "shortcut must be callable: " .. keys)
    binds[keys] = callback
  end,
  workspace_rule = function(rule) rules[tonumber(rule.workspace)] = rule end,
  config = function(value) config = value end,
  env = noop, layer_rule = noop, monitor = noop, window_rule = noop, on = noop,
  dsp = {
    exec_cmd = action, focus = function(args) return function() monitor_focus = args.monitor end end,
    window = { close = action, fullscreen = action, resize = action, float = action },
  },
}
dofile(config_file)
assert(controls[1][1] == "setup" and controls[1][2] == (profile == "jwilger-t14"))
assert(config.binds.window_direction_monitor_fallback)
local function check(keys, method, value)
  assert(binds[keys], "missing shortcut: " .. keys)()
  local last = controls[#controls]
  assert(last[1] == method and last[2] == value, "wrong shortcut: " .. keys)
end
for n = 1, 9 do
  check("SUPER + " .. n, "workspace", n)
  check("SUPER + SHIFT + " .. n, "move_to_workspace", n)
  assert(rules[n] and rules[n].persistent and rules[n].layout == "scrolling")
  assert(rules[n].monitor == (profile == "jwilger-t14" and "desc:Apple Computer Inc StudioDisplay" or "DP-3"))
  if profile == "jwilger-t14" then
    local peer = assert(rules[n + 10])
    assert(peer.monitor == "eDP-1" and peer.default_name == n .. "-laptop" and peer.persistent)
  else assert(not rules[n + 10]) end
end
for key, dir in pairs({ H = "l", J = "d", K = "u", L = "r", LEFT = "l", DOWN = "d", UP = "u", RIGHT = "r" }) do
  check("SUPER + " .. key, "focus", dir)
  check("SUPER + SHIFT + " .. key, "move", dir)
end
for key, dir in pairs({ H = "l", L = "r", LEFT = "l", RIGHT = "r" }) do
  check("SUPER + CTRL + SHIFT + " .. key, "move_to_monitor", dir)
  assert(binds["SUPER + CTRL + " .. key])()
  assert(monitor_focus == dir, "wrong monitor focus shortcut")
end
check("SUPER + BRACKETLEFT", "move_to_monitor", "l")
check("SUPER + BRACKETRIGHT", "move_to_monitor", "r")
check("SUPER + C", "scrolling", "fit active")
check("SUPER + R", "scrolling", "colresize +conf")
check("SUPER + MINUS", "scrolling", "colresize -0.1")
check("SUPER + EQUAL", "scrolling", "colresize +0.1")
assert(binds["SCROLL_LOCK"] and binds["SUPER + RETURN"] and binds["SUPER + SPACE"])
print("ok - generated " .. profile .. " Lua, bindings and workspace rules")
