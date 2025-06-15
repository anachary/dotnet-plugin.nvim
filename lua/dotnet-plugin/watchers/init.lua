-- dotnet-plugin.nvim - File Watcher Management
-- Real-time file change detection for automatic cache invalidation

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')
local handlers = require('dotnet-plugin.watchers.handlers')
local filters = require('dotnet-plugin.watchers.filters')

-- Watcher state
local watchers = {}
local watcher_initialized = false

--- Initialize the file watcher system
--- @return boolean success True if watchers were initialized successfully
function M.setup()
  if watcher_initialized then
    return true
  end

  local watcher_config = config.get_value("watchers") or {}
  
  if not watcher_config.enabled then
    logger.debug("File watchers disabled in configuration")
    return true
  end

  -- Check if Neovim supports file watching
  if not vim.fn.has('nvim-0.8') then
    logger.warn("File watchers require Neovim 0.8+, disabling watchers")
    return false
  end

  logger.info("Initializing file watcher system")
  
  -- Subscribe to relevant events
  M._setup_event_handlers()
  
  watcher_initialized = true
  logger.info("File watcher system initialized successfully")
  return true
end

--- Check if file watchers are available and initialized
--- @return boolean available True if watchers are ready for use
function M.is_available()
  return watcher_initialized and vim.fn.has('nvim-0.8') == 1
end

--- Watch a solution file and its projects
--- @param solution_path string Path to the solution file
--- @param solution_data table Solution data with project information
--- @return boolean success True if watching was set up successfully
function M.watch_solution(solution_path, solution_data)
  if not M.is_available() then
    return false
  end

  local abs_path = vim.fn.fnamemodify(solution_path, ':p')
  
  -- Don't watch the same solution twice
  if watchers[abs_path] then
    logger.debug("Solution already being watched", { path = abs_path })
    return true
  end

  logger.debug("Setting up solution watcher", { path = abs_path })

  -- Watch the solution file itself
  local solution_watcher = M._create_file_watcher(abs_path, function(path, event)
    handlers.handle_solution_change(path, event, solution_data)
  end)

  if not solution_watcher then
    logger.error("Failed to create solution file watcher", { path = abs_path })
    return false
  end

  -- Watch all project files in the solution
  local project_watchers = {}
  for _, project in ipairs(solution_data.projects or {}) do
    if project.path then
      local project_abs_path = vim.fn.fnamemodify(project.path, ':p')
      local project_watcher = M._create_file_watcher(project_abs_path, function(path, event)
        handlers.handle_project_change(path, event, solution_data)
      end)
      
      if project_watcher then
        table.insert(project_watchers, project_watcher)
        logger.debug("Watching project file", { path = project_abs_path })
      else
        logger.warn("Failed to watch project file", { path = project_abs_path })
      end
    end
  end

  -- Store watcher information
  watchers[abs_path] = {
    solution_watcher = solution_watcher,
    project_watchers = project_watchers,
    solution_data = solution_data,
    created_at = os.time()
  }

  logger.info("Solution watcher setup complete", { 
    solution = abs_path,
    projects_watched = #project_watchers
  })

  return true
end

--- Watch a single project file
--- @param project_path string Path to the project file
--- @return boolean success True if watching was set up successfully
function M.watch_project(project_path)
  if not M.is_available() then
    return false
  end

  local abs_path = vim.fn.fnamemodify(project_path, ':p')
  
  -- Don't watch the same project twice (unless it's part of a solution)
  if watchers[abs_path] and not watchers[abs_path].is_standalone then
    logger.debug("Project already being watched", { path = abs_path })
    return true
  end

  logger.debug("Setting up standalone project watcher", { path = abs_path })

  local project_watcher = M._create_file_watcher(abs_path, function(path, event)
    handlers.handle_standalone_project_change(path, event)
  end)

  if not project_watcher then
    logger.error("Failed to create project file watcher", { path = abs_path })
    return false
  end

  watchers[abs_path] = {
    project_watcher = project_watcher,
    is_standalone = true,
    created_at = os.time()
  }

  logger.info("Standalone project watcher setup complete", { path = abs_path })
  return true
end

--- Stop watching a solution or project
--- @param file_path string Path to stop watching
--- @return boolean success True if watching was stopped successfully
function M.unwatch(file_path)
  local abs_path = vim.fn.fnamemodify(file_path, ':p')
  local watcher_info = watchers[abs_path]
  
  if not watcher_info then
    logger.debug("No watcher found for path", { path = abs_path })
    return true
  end

  logger.debug("Stopping file watcher", { path = abs_path })

  -- Stop solution watcher
  if watcher_info.solution_watcher then
    watcher_info.solution_watcher:stop()
  end

  -- Stop project watchers
  if watcher_info.project_watchers then
    for _, project_watcher in ipairs(watcher_info.project_watchers) do
      project_watcher:stop()
    end
  end

  -- Stop standalone project watcher
  if watcher_info.project_watcher then
    watcher_info.project_watcher:stop()
  end

  watchers[abs_path] = nil
  logger.info("File watcher stopped", { path = abs_path })
  return true
end

--- Get information about active watchers
--- @return table stats Watcher statistics and information
function M.get_stats()
  local solution_count = 0
  local project_count = 0
  local standalone_count = 0
  
  for _, watcher_info in pairs(watchers) do
    if watcher_info.solution_watcher then
      solution_count = solution_count + 1
      project_count = project_count + #(watcher_info.project_watchers or {})
    elseif watcher_info.is_standalone then
      standalone_count = standalone_count + 1
    end
  end

  return {
    available = M.is_available(),
    solutions_watched = solution_count,
    projects_watched = project_count,
    standalone_projects = standalone_count,
    total_watchers = solution_count + project_count + standalone_count
  }
end

--- Create a file watcher for a specific path
--- @param file_path string Path to watch
--- @param callback function Callback to execute on file changes
--- @return table|nil watcher Watcher object or nil on failure
function M._create_file_watcher(file_path, callback)
  if not vim.fn.filereadable(file_path) then
    logger.warn("Cannot watch non-existent file", { path = file_path })
    return nil
  end

  -- Create the fs_event handle
  local fs_event = vim.loop.new_fs_event()
  if not fs_event then
    logger.error("Failed to create fs_event handle", { path = file_path })
    return nil
  end

  -- Start watching the file
  local ok, err = pcall(fs_event.start, fs_event, file_path, {}, function(err, filename, events)
    if err then
      logger.error("File watcher error", { path = file_path, error = err })
      return
    end

    -- Filter out irrelevant events
    if not filters.should_process_event(file_path, filename, events) then
      return
    end

    logger.debug("File change detected", {
      path = file_path,
      filename = filename,
      events = events
    })

    -- Call the provided callback
    callback(file_path, {
      filename = filename,
      events = events,
      timestamp = os.time()
    })
  end)

  if not ok then
    logger.error("Failed to start file watcher", { path = file_path, error = err })
    fs_event:close()
    return nil
  end

  return fs_event
end

--- Setup event handlers for integration with other systems
function M._setup_event_handlers()
  -- Watch solutions when they are loaded
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    if config.get_value("watchers.auto_watch_solutions") then
      M.watch_solution(data.path, data.solution)
    end
  end)

  -- Watch projects when they are loaded standalone
  events.subscribe(events.EVENTS.PROJECT_LOADED, function(data)
    if config.get_value("watchers.auto_watch_projects") then
      M.watch_project(data.path)
    end
  end)

  -- Stop watching when solutions/projects are unloaded
  events.subscribe(events.EVENTS.SOLUTION_UNLOADED, function(data)
    M.unwatch(data.path)
  end)

  events.subscribe(events.EVENTS.PROJECT_UNLOADED, function(data)
    M.unwatch(data.path)
  end)
end

--- Stop all watchers and cleanup
function M.shutdown()
  if not watcher_initialized then
    return
  end

  logger.info("Shutting down file watcher system")
  
  -- Stop all active watchers
  for path, _ in pairs(watchers) do
    M.unwatch(path)
  end

  watchers = {}
  watcher_initialized = false
  logger.debug("File watcher system shutdown complete")
end

return M
