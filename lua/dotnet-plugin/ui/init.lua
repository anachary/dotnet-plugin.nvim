-- UI management for dotnet-plugin.nvim
-- Coordinates all UI components and provides unified interface

local M = {}

local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

-- UI components
local solution_explorer = require('dotnet-plugin.ui.solution_explorer')
local statusline = require('dotnet-plugin.ui.statusline')
local notifications = require('dotnet-plugin.ui.notifications')

-- UI state
local ui_initialized = false
local active_components = {}

--- Setup the UI system
--- @return boolean success True if UI was initialized successfully
function M.setup()
  if ui_initialized then
    return true
  end

  local ui_config = config.get_value("ui") or {}
  
  if not ui_config.enabled then
    logger.info("UI components disabled in configuration")
    return true
  end

  logger.info("Initializing UI components")

  -- Initialize UI components
  local success = true
  
  -- Setup solution explorer
  if ui_config.solution_explorer and ui_config.solution_explorer.enabled then
    if solution_explorer.setup() then
      active_components.solution_explorer = true
      logger.debug("Solution explorer initialized")
    else
      logger.error("Failed to initialize solution explorer")
      success = false
    end
  end

  -- Setup status line integration
  if ui_config.statusline and ui_config.statusline.enabled then
    if statusline.setup() then
      active_components.statusline = true
      logger.debug("Status line integration initialized")
    else
      logger.error("Failed to initialize status line integration")
      success = false
    end
  end

  -- Setup notifications
  if ui_config.notifications and ui_config.notifications.enabled then
    if notifications.setup() then
      active_components.notifications = true
      logger.debug("Notification system initialized")
    else
      logger.error("Failed to initialize notification system")
      success = false
    end
  end

  if success then
    M._setup_event_handlers()
    M._setup_commands()
    ui_initialized = true
    logger.info("UI system initialized successfully")
  end

  return success
end

--- Setup event handlers for UI integration
function M._setup_event_handlers()
  -- Solution events for UI updates
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M.on_solution_loaded(data)
  end)

  events.subscribe(events.EVENTS.SOLUTION_UNLOADED, function(data)
    M.on_solution_unloaded(data)
  end)

  -- Project events for UI updates
  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M.on_project_changed(data)
  end)

  -- Build events for status updates
  events.subscribe(events.EVENTS.BUILD_STARTED, function(data)
    M.on_build_started(data)
  end)

  events.subscribe(events.EVENTS.BUILD_PROGRESS, function(data)
    M.on_build_progress(data)
  end)

  events.subscribe(events.EVENTS.BUILD_COMPLETED, function(data)
    M.on_build_completed(data)
  end)

  events.subscribe(events.EVENTS.BUILD_FAILED, function(data)
    M.on_build_failed(data)
  end)
end

--- Setup user commands for UI components
function M._setup_commands()
  -- Solution Explorer commands
  vim.api.nvim_create_user_command('DotnetSolutionExplorer', function()
    M.toggle_solution_explorer()
  end, { desc = 'Toggle .NET Solution Explorer' })

  vim.api.nvim_create_user_command('DotnetSolutionExplorerOpen', function()
    M.open_solution_explorer()
  end, { desc = 'Open .NET Solution Explorer' })

  vim.api.nvim_create_user_command('DotnetSolutionExplorerClose', function()
    M.close_solution_explorer()
  end, { desc = 'Close .NET Solution Explorer' })

  -- Status line commands
  vim.api.nvim_create_user_command('DotnetStatusRefresh', function()
    M.refresh_status()
  end, { desc = 'Refresh .NET status information' })
end

--- Handle solution loaded event
--- @param data table Solution data
function M.on_solution_loaded(data)
  if active_components.solution_explorer then
    solution_explorer.load_solution(data)
  end
  
  if active_components.statusline then
    statusline.update_solution_status(data)
  end
  
  if active_components.notifications then
    notifications.show_info("Solution loaded: " .. vim.fn.fnamemodify(data.path, ":t"))
  end
end

--- Handle solution unloaded event
--- @param data table Solution data
function M.on_solution_unloaded(data)
  if active_components.solution_explorer then
    solution_explorer.clear_solution()
  end
  
  if active_components.statusline then
    statusline.clear_solution_status()
  end
end

--- Handle project changed event
--- @param data table Project data
function M.on_project_changed(data)
  if active_components.solution_explorer then
    solution_explorer.refresh_project(data)
  end
end

--- Handle build started event
--- @param data table Build data
function M.on_build_started(data)
  if active_components.statusline then
    statusline.update_build_status("building", data)
  end
  
  if active_components.notifications then
    notifications.show_info("Build started: " .. (data.project or "Solution"))
  end
end

--- Handle build progress event
--- @param data table Build progress data
function M.on_build_progress(data)
  if active_components.statusline then
    statusline.update_build_progress(data)
  end
end

--- Handle build completed event
--- @param data table Build result data
function M.on_build_completed(data)
  if active_components.statusline then
    statusline.update_build_status("success", data)
  end
  
  if active_components.notifications then
    notifications.show_success("Build completed successfully")
  end
end

--- Handle build failed event
--- @param data table Build error data
function M.on_build_failed(data)
  if active_components.statusline then
    statusline.update_build_status("error", data)
  end
  
  if active_components.notifications then
    notifications.show_error("Build failed: " .. (data.error or "Unknown error"))
  end
end

--- Toggle solution explorer
function M.toggle_solution_explorer()
  if active_components.solution_explorer then
    solution_explorer.toggle()
  else
    logger.warn("Solution explorer is not enabled")
  end
end

--- Open solution explorer
function M.open_solution_explorer()
  if active_components.solution_explorer then
    solution_explorer.open()
  else
    logger.warn("Solution explorer is not enabled")
  end
end

--- Close solution explorer
function M.close_solution_explorer()
  if active_components.solution_explorer then
    solution_explorer.close()
  else
    logger.warn("Solution explorer is not enabled")
  end
end

--- Refresh status information
function M.refresh_status()
  if active_components.statusline then
    statusline.refresh()
  end
end

--- Get UI component status
--- @return table Component status information
function M.get_status()
  return {
    initialized = ui_initialized,
    active_components = active_components
  }
end

--- Shutdown the UI system
function M.shutdown()
  if ui_initialized then
    if active_components.solution_explorer then
      solution_explorer.shutdown()
    end
    
    if active_components.statusline then
      statusline.shutdown()
    end
    
    if active_components.notifications then
      notifications.shutdown()
    end
    
    active_components = {}
    ui_initialized = false
    logger.info("UI system shutdown")
  end
end

return M
