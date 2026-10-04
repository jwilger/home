-- Hyprland 0.55 Lua API. Keep layout-specific dispatchers behind runtime checks:
-- Noctalia changes the active workspace's layout without reloading keybindings.
local M = {}
local per_monitor = false
local configured = false
local studio_description = "Apple Computer Inc StudioDisplay"

local function dispatch(action)
  hl.dispatch(action)
end

local function logical_workspace(workspace)
  if not workspace or workspace.special then return nil end
  local id = workspace.id
  if id >= 1 and id <= 9 then return id end
  if id >= 11 and id <= 19 then return id - 10 end
  return nil
end

local function monitors()
  local studio, laptop
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name == "eDP-1" then laptop = monitor end
    if (monitor.description or ""):sub(1, #studio_description) == studio_description then
      studio = monitor
    end
  end
  return studio, laptop
end

local function workspace_id(number, monitor)
  if per_monitor and monitor and monitor.name == "eDP-1" then return number + 10 end
  return number
end

function M.workspace(number)
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  local id = workspace_id(number, monitor)
  if monitor.active_workspace and monitor.active_workspace.id == id then return end
  dispatch(hl.dsp.focus({ workspace = tostring(id) }))
end

function M.move_to_workspace(number)
  local window = hl.get_active_window()
  if not window then return end
  dispatch(hl.dsp.window.move({
    workspace = tostring(workspace_id(number, window.monitor)), follow = true,
  }))
end

function M.move_to_monitor(direction)
  local window = hl.get_active_window()
  if not window then return end
  if not per_monitor then
    dispatch(hl.dsp.window.move({ monitor = direction, follow = true }))
    return
  end
  local studio, laptop = monitors()
  if not studio or not laptop then return end
  local target
  if direction == "l" and window.monitor.name == studio.name then target = laptop end
  if direction == "r" and window.monitor.name == laptop.name then target = studio end
  local number = logical_workspace(window.workspace)
  if not target or not number then return end
  dispatch(hl.dsp.window.move({
    workspace = tostring(workspace_id(number, target)), follow = true,
  }))
end

local function tiled_window()
  local window = hl.get_active_window()
  if not window or window.floating then return nil end
  return window
end

function M.focus(direction)
  local window = tiled_window()
  local layout = window and window.workspace.tiled_layout
  if layout == "monocle" then
    dispatch(hl.dsp.layout((direction == "l" or direction == "u") and "cycleprev" or "cyclenext"))
  elseif layout == "scrolling" and (direction == "l" or direction == "r") then
    dispatch(hl.dsp.layout("focus " .. direction))
    -- Scrolling stops at the edge; allow keyboard focus to reach the next monitor.
    if hl.get_active_window() == window then dispatch(hl.dsp.focus({ direction = direction })) end
  else
    dispatch(hl.dsp.focus({ direction = direction }))
  end
end

function M.move(direction)
  if not hl.get_active_window() then return end
  local window = tiled_window()
  local column = window and window.layout and window.layout.column
  if window and window.workspace.tiled_layout == "scrolling" and column
      and (direction == "l" or direction == "r") then
    local adjacent = column.index + (direction == "l" and -1 or 1)
    for _, other in ipairs(hl.get_workspace_windows(window.workspace)) do
      local other_column = other.layout and other.layout.column
      if other_column and other_column.index == adjacent then
        dispatch(hl.dsp.layout("swapcol " .. direction))
        return
      end
    end
  end
  -- Also handles floating windows, empty workspaces, and the scrolling edge.
  -- Native directional movement can cross to the other monitor's workspace.
  dispatch(hl.dsp.window.move({ direction = direction }))
end

function M.scrolling(command)
  local window = tiled_window()
  if window and window.workspace.tiled_layout == "scrolling" then
    dispatch(hl.dsp.layout(command))
  end
end

function M.setup(enable_per_monitor)
  if configured then return end
  configured = true
  per_monitor = enable_per_monitor
end

return M
