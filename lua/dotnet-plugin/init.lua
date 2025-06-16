-- dotnet-plugin.nvim - Main module
-- This is the entry point for the .NET Development Suite

local M = {}

-- Import core modules
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')
local cache = require('dotnet-plugin.cache')
local watchers = require('dotnet-plugin.watchers')
local lsp = require('dotnet-plugin.lsp')
local ui = require('dotnet-plugin.ui')
local build = require('dotnet-plugin.build')

-- Import Phase 2.1 components
local debug = require('dotnet-plugin.debug')
local test = require('dotnet-plugin.test')
local refactor = require('dotnet-plugin.refactor')

-- Plugin state
M._initialized = false

--- Setup the plugin with user configuration
--- @param opts table|nil User configuration options
function M.setup(opts)
  if M._initialized then
    return
  end

  -- Initialize configuration first
  config.setup(opts or {})
  
  -- Initialize logging
  logger.setup(config.get().logging)
  
  -- Initialize event system
  events.setup()

  -- Initialize cache system
  if config.get_value("cache.enabled") then
    local cache_success = cache.setup()
    if cache_success then
      logger.info("Cache system initialized")

      -- Cleanup old cache entries on startup if configured
      if config.get_value("cache.cleanup_on_startup") then
        cache.cleanup(config.get_value("cache.max_age_days"))
      end
    else
      logger.warn("Cache system initialization failed, continuing without cache")
    end
  else
    logger.debug("Cache system disabled in configuration")
  end

  -- Initialize file watcher system
  if config.get_value("watchers.enabled") then
    local watcher_success = watchers.setup()
    if watcher_success then
      logger.info("File watcher system initialized")
    else
      logger.warn("File watcher system initialization failed, continuing without watchers")
    end
  else
    logger.debug("File watcher system disabled in configuration")
  end

  -- Initialize LSP integration
  if config.get_value("lsp.enabled") then
    local lsp_success = lsp.setup()
    if lsp_success then
      logger.info("LSP integration initialized")

      -- Ensure LSP server is installed if auto-install is enabled
      if config.get_value("lsp.auto_install") then
        local installer = require('dotnet-plugin.lsp.installer')
        if not installer.is_installed() then
          logger.info("LSP server not found, attempting automatic installation...")
          vim.schedule(function()
            installer.ensure_installed()
          end)
        end
      end
    else
      logger.warn("LSP integration initialization failed, continuing without LSP")
    end
  else
    logger.debug("LSP integration disabled in configuration")
  end

  -- Initialize UI components
  if config.get_value("ui.enabled") then
    local ui_success = ui.setup()
    if ui_success then
      logger.info("UI components initialized")
    else
      logger.warn("UI components initialization failed, continuing without UI")
    end
  else
    logger.debug("UI components disabled in configuration")
  end

  -- Initialize build system
  if config.get_value("build.enabled") then
    local build_success = build.setup()
    if build_success then
      logger.info("Build system initialized")
    else
      logger.warn("Build system initialization failed, continuing without build integration")
    end
  else
    logger.debug("Build system disabled in configuration")
  end

  -- Initialize debug integration (Phase 2.1)
  if config.get_value("debug.enabled") then
    local debug_success = debug.setup()
    if debug_success then
      logger.info("Debug integration initialized")
    else
      logger.warn("Debug integration initialization failed, continuing without debugging")
    end
  else
    logger.debug("Debug integration disabled in configuration")
  end

  -- Initialize test framework (Phase 2.1)
  if config.get_value("test.enabled") then
    local test_success = test.setup()
    if test_success then
      logger.info("Test framework initialized")
    else
      logger.warn("Test framework initialization failed, continuing without testing")
    end
  else
    logger.debug("Test framework disabled in configuration")
  end

  -- Initialize refactoring tools (Phase 2.1)
  if config.get_value("refactor.enabled") then
    local refactor_success = refactor.setup()
    if refactor_success then
      logger.info("Refactoring tools initialized")
    else
      logger.warn("Refactoring tools initialization failed, continuing without refactoring")
    end
  else
    logger.debug("Refactoring tools disabled in configuration")
  end

  -- Log successful initialization
  logger.info("dotnet-plugin.nvim Phase 2.1 initialized successfully")

  M._initialized = true
end

--- Get the current configuration
--- @return table Current configuration
function M.get_config()
  return config.get()
end

--- Check if plugin is initialized
--- @return boolean True if initialized
function M.is_initialized()
  return M._initialized
end

--- Get cache statistics
--- @return table Cache statistics
function M.get_cache_stats()
  return cache.get_stats()
end

--- Invalidate cache for a specific file
--- @param file_path string Path to invalidate
--- @return boolean Success
function M.invalidate_cache(file_path)
  return cache.invalidate(file_path)
end

--- Cleanup old cache entries
--- @param max_age_days number|nil Maximum age in days
--- @return boolean Success
function M.cleanup_cache(max_age_days)
  return cache.cleanup(max_age_days)
end

--- Get file watcher statistics
--- @return table Watcher statistics
function M.get_watcher_stats()
  return watchers.get_stats()
end

--- Watch a solution file and its projects
--- @param solution_path string Path to the solution file
--- @param solution_data table Solution data
--- @return boolean Success
function M.watch_solution(solution_path, solution_data)
  return watchers.watch_solution(solution_path, solution_data)
end

--- Watch a project file
--- @param project_path string Path to the project file
--- @return boolean Success
function M.watch_project(project_path)
  return watchers.watch_project(project_path)
end

--- Stop watching a file
--- @param file_path string Path to stop watching
--- @return boolean Success
function M.unwatch(file_path)
  return watchers.unwatch(file_path)
end

--- Get LSP status
--- @return table LSP status and information
function M.get_lsp_status()
  return lsp.status()
end

--- Get LSP workspace information
--- @return table Workspace configuration
function M.get_lsp_workspace_info()
  return lsp.workspace_info()
end

--- Restart LSP client for current buffer
--- @return boolean success True if restart was successful
function M.restart_lsp()
  return lsp.restart()
end

--- Install Roslyn Language Server
--- @param method string|nil Installation method (optional)
--- @return boolean success True if installation was successful
function M.install_lsp_server(method)
  return lsp.install_server(method)
end

--- Check if Roslyn Language Server is installed
--- @return boolean installed True if server is available
function M.is_lsp_server_installed()
  return lsp.is_server_installed()
end

--- Ensure Roslyn Language Server is installed
--- @return boolean success True if server is available after ensuring installation
function M.ensure_lsp_server_installed()
  return lsp.ensure_server_installed()
end

--- Build current solution or project
--- @param target string|nil Target to build
--- @return number|nil Build ID
function M.build(target)
  return build.build_solution(target)
end

--- Rebuild current solution or project
--- @param target string|nil Target to rebuild
--- @return number|nil Build ID
function M.rebuild(target)
  return build.rebuild_solution(target)
end

--- Clean current solution or project
--- @param target string|nil Target to clean
--- @return number|nil Build ID
function M.clean(target)
  return build.clean_solution(target)
end

--- Restore NuGet packages
--- @param target string|nil Target to restore
--- @return number|nil Build ID
function M.restore(target)
  return build.restore_packages(target)
end

--- Toggle solution explorer
function M.toggle_solution_explorer()
  ui.toggle_solution_explorer()
end

--- Open solution explorer
function M.open_solution_explorer()
  ui.open_solution_explorer()
end

--- Close solution explorer
function M.close_solution_explorer()
  ui.close_solution_explorer()
end

--- Shutdown the plugin
function M.shutdown()
  if M._initialized then
    -- Shutdown Phase 2.1 components
    refactor.shutdown()
    test.shutdown()
    debug.shutdown()

    -- Shutdown Phase 1 components
    build.shutdown()
    ui.shutdown()
    lsp.shutdown()
    watchers.shutdown()
    cache.shutdown()

    logger.info("dotnet-plugin.nvim shutdown")
    M._initialized = false
  end
end

return M
