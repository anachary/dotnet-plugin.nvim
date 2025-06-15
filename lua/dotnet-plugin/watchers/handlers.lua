-- dotnet-plugin.nvim - File Change Handlers
-- Handle different types of file change events

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')

--- Handle solution file changes
--- @param solution_path string Path to the changed solution file
--- @param event table Event information
--- @param solution_data table Current solution data
function M.handle_solution_change(solution_path, event, solution_data)
  logger.info("Solution file changed", { 
    path = solution_path, 
    events = event.events 
  })

  -- Invalidate solution cache
  if cache.is_available() then
    local invalidated = cache.invalidate(solution_path)
    logger.debug("Solution cache invalidated", { 
      path = solution_path, 
      success = invalidated 
    })
  end

  -- Emit solution changed event
  events.emit(events.EVENTS.SOLUTION_CHANGED, {
    path = solution_path,
    event = event,
    previous_data = solution_data
  })

  -- Schedule solution reload if auto-reload is enabled
  local config = require('dotnet-plugin.core.config')
  if config.get_value("watchers.auto_reload_on_change") then
    M._schedule_solution_reload(solution_path)
  end
end

--- Handle project file changes
--- @param project_path string Path to the changed project file
--- @param event table Event information
--- @param solution_data table Parent solution data (if any)
function M.handle_project_change(project_path, event, solution_data)
  logger.info("Project file changed", { 
    path = project_path, 
    events = event.events 
  })

  -- Invalidate project cache
  if cache.is_available() then
    local invalidated = cache.invalidate(project_path)
    logger.debug("Project cache invalidated", { 
      path = project_path, 
      success = invalidated 
    })
  end

  -- If this project is part of a solution, also invalidate solution cache
  if solution_data and cache.is_available() then
    local solution_path = solution_data.path
    if solution_path then
      cache.invalidate(solution_path)
      logger.debug("Parent solution cache invalidated", { 
        solution = solution_path,
        project = project_path
      })
    end
  end

  -- Emit project changed event
  events.emit(events.EVENTS.PROJECT_CHANGED, {
    path = project_path,
    event = event,
    solution_data = solution_data
  })

  -- Check if this is a significant change that requires dependency re-analysis
  if M._is_dependency_affecting_change(project_path, event) then
    M._schedule_dependency_analysis(project_path, solution_data)
  end

  -- Schedule project reload if auto-reload is enabled
  local config = require('dotnet-plugin.core.config')
  if config.get_value("watchers.auto_reload_on_change") then
    M._schedule_project_reload(project_path)
  end
end

--- Handle standalone project file changes (not part of a solution)
--- @param project_path string Path to the changed project file
--- @param event table Event information
function M.handle_standalone_project_change(project_path, event)
  logger.info("Standalone project file changed", { 
    path = project_path, 
    events = event.events 
  })

  -- Invalidate project cache
  if cache.is_available() then
    local invalidated = cache.invalidate(project_path)
    logger.debug("Standalone project cache invalidated", { 
      path = project_path, 
      success = invalidated 
    })
  end

  -- Emit project changed event
  events.emit(events.EVENTS.PROJECT_CHANGED, {
    path = project_path,
    event = event,
    is_standalone = true
  })

  -- Schedule project reload if auto-reload is enabled
  local config = require('dotnet-plugin.core.config')
  if config.get_value("watchers.auto_reload_on_change") then
    M._schedule_project_reload(project_path)
  end
end

--- Check if a project change affects dependencies
--- @param project_path string Path to the project file
--- @param event table Event information
--- @return boolean affects_dependencies True if dependencies might be affected
function M._is_dependency_affecting_change(project_path, event)
  -- For now, assume any project file change could affect dependencies
  -- In the future, we could parse the file to check if PackageReference
  -- or ProjectReference elements were modified
  return true
end

--- Schedule solution reload with debouncing
--- @param solution_path string Path to the solution file
function M._schedule_solution_reload(solution_path)
  local config = require('dotnet-plugin.core.config')
  local delay = config.get_value("watchers.reload_delay_ms") or 500

  -- Cancel any existing reload timer for this solution
  local timer_key = "solution_reload_" .. solution_path
  M._cancel_timer(timer_key)

  -- Schedule new reload
  M._set_timer(timer_key, delay, function()
    logger.debug("Auto-reloading solution", { path = solution_path })
    
    -- Emit reload request event
    events.emit(events.EVENTS.SOLUTION_RELOAD_REQUESTED, {
      path = solution_path,
      reason = "file_changed"
    })
  end)
end

--- Schedule project reload with debouncing
--- @param project_path string Path to the project file
function M._schedule_project_reload(project_path)
  local config = require('dotnet-plugin.core.config')
  local delay = config.get_value("watchers.reload_delay_ms") or 500

  -- Cancel any existing reload timer for this project
  local timer_key = "project_reload_" .. project_path
  M._cancel_timer(timer_key)

  -- Schedule new reload
  M._set_timer(timer_key, delay, function()
    logger.debug("Auto-reloading project", { path = project_path })
    
    -- Emit reload request event
    events.emit(events.EVENTS.PROJECT_RELOAD_REQUESTED, {
      path = project_path,
      reason = "file_changed"
    })
  end)
end

--- Schedule dependency analysis
--- @param project_path string Path to the project file
--- @param solution_data table Solution data (if any)
function M._schedule_dependency_analysis(project_path, solution_data)
  local config = require('dotnet-plugin.core.config')
  local delay = config.get_value("watchers.dependency_analysis_delay_ms") or 1000

  local timer_key = "dependency_analysis_" .. project_path
  M._cancel_timer(timer_key)

  M._set_timer(timer_key, delay, function()
    logger.debug("Scheduling dependency analysis", { path = project_path })
    
    events.emit(events.EVENTS.DEPENDENCY_ANALYSIS_REQUESTED, {
      project_path = project_path,
      solution_data = solution_data,
      reason = "project_changed"
    })
  end)
end

-- Timer management for debouncing
local active_timers = {}

--- Set a timer with automatic cleanup
--- @param key string Unique timer key
--- @param delay number Delay in milliseconds
--- @param callback function Function to call when timer expires
function M._set_timer(key, delay, callback)
  local timer = vim.loop.new_timer()
  active_timers[key] = timer
  
  timer:start(delay, 0, function()
    -- Remove from active timers
    active_timers[key] = nil
    
    -- Execute callback
    vim.schedule(callback)
    
    -- Close timer
    if not timer:is_closing() then
      timer:close()
    end
  end)
end

--- Cancel an active timer
--- @param key string Timer key to cancel
function M._cancel_timer(key)
  local timer = active_timers[key]
  if timer then
    if not timer:is_closing() then
      timer:close()
    end
    active_timers[key] = nil
  end
end

--- Cleanup all active timers
function M.cleanup_timers()
  for key, timer in pairs(active_timers) do
    if not timer:is_closing() then
      timer:close()
    end
  end
  active_timers = {}
end

return M
