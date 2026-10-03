-- Hyprland 0.55 Lua API. Keep layout-specific dispatchers behind runtime checks:
-- Noctalia changes the active workspace's layout without reloading keybindings.
local M = {}
local paired = false
local syncing = false
local configured = false
local last_number
local workspace_generation = 0
local hotplug_generation = 0
local hotplug_pending = false
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
  if paired and monitor and monitor.name == "eDP-1" then return number + 10 end
  return number
end

local function has_active_special()
  local studio, laptop = monitors()
  return (studio and studio.active_special_workspace)
      or (laptop and laptop.active_special_workspace)
end

-- v0.55 has no monitor:set_workspace. Visit the peer first and the original
-- monitor last, then restore the pointer warped by the cross-monitor dispatch.
local function sync_pair(number, origin, saved_cursor)
  local studio, laptop = monitors()
  if not paired or syncing or not studio or not laptop or not origin then return end
  local peer
  if origin.name == studio.name then peer = laptop
  elseif origin.name == laptop.name then peer = studio
  else return end
  local own_id, peer_id = workspace_id(number, origin), workspace_id(number, peer)
  local own_matches = origin.active_workspace and origin.active_workspace.id == own_id
  if own_matches and peer.active_workspace and peer.active_workspace.id == peer_id then return end

  local cursor = saved_cursor or hl.get_cursor_pos()
  syncing = true
  local ok, err = pcall(function()
    if not peer.active_workspace or peer.active_workspace.id ~= peer_id then
      dispatch(hl.dsp.focus({ workspace = tostring(peer_id) }))
    end
    if own_matches then
      -- Focusing an already active empty workspace is a compositor no-op. Focus
      -- its monitor explicitly so keyboard focus cannot remain on the peer.
      dispatch(hl.dsp.focus({ monitor = origin.name }))
    else
      dispatch(hl.dsp.focus({ workspace = tostring(own_id) }))
    end
    dispatch(hl.dsp.cursor.move(cursor))
  end)
  syncing = false
  if not ok then error(err) end
end

local function invalidate_workspace_sync()
  workspace_generation = workspace_generation + 1
end

local function focus_single(number, origin, saved_cursor)
  local id = workspace_id(number, origin)
  if origin.active_workspace and origin.active_workspace.id == id then return end
  local cursor = saved_cursor or hl.get_cursor_pos()
  syncing = true
  local ok, err = pcall(function()
    dispatch(hl.dsp.focus({ workspace = tostring(id) }))
    dispatch(hl.dsp.cursor.move(cursor))
  end)
  syncing = false
  if not ok then error(err) end
end

function M.workspace(number)
  last_number = number
  invalidate_workspace_sync()
  local origin = hl.get_active_monitor()
  if not origin then return end
  local studio, laptop = monitors()
  if paired and studio and laptop and (origin.name == studio.name or origin.name == laptop.name) then
    sync_pair(number, origin)
  else
    -- An undocked output keeps its own bank. Hyprland preserves windows from
    -- an unplugged output; its migrated workspaces remain accessible in the bar.
    dispatch(hl.dsp.focus({ workspace = tostring(workspace_id(number, origin)) }))
  end
end

function M.move_to_workspace(number)
  local window = hl.get_active_window()
  if not window then return end
  last_number = number
  invalidate_workspace_sync()
  syncing = true
  local ok, err = pcall(function()
    dispatch(hl.dsp.window.move({
      workspace = tostring(workspace_id(number, window.monitor)), follow = true,
    }))
  end)
  syncing = false
  if not ok then error(err) end
  sync_pair(number, window.monitor)
end

function M.move_to_monitor(direction)
  local window = hl.get_active_window()
  if not window then return end
  if not paired then
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
  -- Native directional movement can cross to the peer's active paired workspace.
  dispatch(hl.dsp.window.move({ direction = direction }))
end

function M.scrolling(command)
  local window = tiled_window()
  if window and window.workspace.tiled_layout == "scrolling" then
    dispatch(hl.dsp.layout(command))
  end
end

function M.setup(enable_pairing)
  if configured then return end
  configured = true
  paired = enable_pairing
  if not paired then return end

  hl.on("workspace.active", function(workspace)
    if syncing or hotplug_pending then return end
    local number = logical_workspace(workspace)
    local origin = workspace and workspace.monitor
    -- Ignore foreign/special workspaces and temporarily migrated banks during hotplug.
    if not number or not origin or workspace.id ~= workspace_id(number, origin) then return end

    invalidate_workspace_sync()
    local generation = workspace_generation
    local origin_name = origin.name
    local workspace_id_at_event = workspace.id
    local cursor = hl.get_cursor_pos()
    -- workspace.active is synchronous. In particular it fires from the middle of
    -- monitor teardown while the disabled monitor is still in get_monitors().
    hl.timer(function()
      if generation ~= workspace_generation or hotplug_pending then return end
      local active_monitor = hl.get_active_monitor()
      local active_workspace = hl.get_active_workspace()
      if not active_monitor or active_monitor.name ~= origin_name
          or not active_workspace or active_workspace.id ~= workspace_id_at_event
          or not active_workspace.monitor or active_workspace.monitor.name ~= origin_name
          or workspace_id_at_event ~= workspace_id(number, active_monitor) then return end
      local studio, laptop = monitors()
      if active_monitor.name ~= (studio and studio.name)
          and active_monitor.name ~= (laptop and laptop.name) then return end
      last_number = number
      if has_active_special() then return end
      sync_pair(number, active_monitor, cursor)
    end, { timeout = 1, type = "oneshot" })
  end)

  local function resync_later(is_hotplug)
    -- config.reloaded also fires during --verify-config, before Hyprland has an
    -- active monitor or an event-loop timer manager.
    if not hl.get_active_monitor() then return end
    invalidate_workspace_sync()
    hotplug_generation = hotplug_generation + 1
    local generation = hotplug_generation
    hotplug_pending = hotplug_pending or is_hotplug
    local cursor = hl.get_cursor_pos()
    -- Persistent workspace relocation is deferred by Hyprland during hotplug.
    hl.timer(function()
      if generation ~= hotplug_generation then return end
      hotplug_pending = false
      if has_active_special() then return end
      local origin = hl.get_active_monitor()
      local number = last_number or logical_workspace(hl.get_active_workspace())
      if not origin or not number then return end
      last_number = number
      local studio, laptop = monitors()
      if studio and laptop then
        sync_pair(number, origin, cursor)
      elseif (studio and origin.name == studio.name) or (laptop and origin.name == laptop.name) then
        focus_single(number, origin, cursor)
      end
    end, { timeout = 100, type = "oneshot" })
  end
  hl.on("hyprland.start", function() resync_later(false) end)
  hl.on("config.reloaded", function() resync_later(false) end)
  hl.on("monitor.added", function() resync_later(true) end)
  hl.on("monitor.removed", function() resync_later(true) end)
end

return M
