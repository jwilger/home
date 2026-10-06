-- Hyprland 0.55 Lua API. Keep layout-specific dispatchers behind runtime checks:
-- Noctalia changes the active workspace's layout without reloading keybindings.
local M = {}
local function dispatch(action)
  hl.dispatch(action)
end

function M.workspace(number)
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  local id = number
  if monitor.active_workspace and monitor.active_workspace.id == id then return end
  dispatch(hl.dsp.focus({ workspace = tostring(id) }))
end

function M.move_to_workspace(number)
  local window = hl.get_active_window()
  if not window then return end
  dispatch(hl.dsp.window.move({
    workspace = tostring(number), follow = true,
  }))
end

function M.move_to_monitor(direction)
  local window = hl.get_active_window()
  if not window then return end
  dispatch(hl.dsp.window.move({ monitor = direction, follow = true }))
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

-- A running compositor can retain the resolved path of an older generation.
-- Its setup call must also release the old persistent workspace rules until login.
function M.setup()
  for number = 1, 9 do
    hl.workspace_rule({ workspace = tostring(number), persistent = false })
    hl.workspace_rule({ workspace = tostring(number + 10), persistent = false })
  end
end

return M
