-- Build system management for dotnet-plugin.nvim
-- Coordinates MSBuild integration and build operations

local M = {}

local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

-- Build components
local msbuild = require('dotnet-plugin.build.msbuild')
local progress = require('dotnet-plugin.build.progress')
local errors = require('dotnet-plugin.build.errors')

-- Build state
local build_initialized = false
local active_builds = {}
local build_counter = 0

--- Setup the build system
--- @return boolean success True if build system was initialized successfully
function M.setup()
  if build_initialized then
    return true
  end

  local build_config = config.get_value("build") or {}
  
  if not build_config.enabled then
    logger.info("Build system disabled in configuration")
    return true
  end

  logger.info("Initializing build system")

  -- Initialize build components
  local success = true
  
  -- Setup MSBuild integration
  if not msbuild.setup() then
    logger.error("Failed to initialize MSBuild integration")
    success = false
  end

  -- Setup progress tracking
  if not progress.setup() then
    logger.error("Failed to initialize build progress tracking")
    success = false
  end

  -- Setup error handling
  if not errors.setup() then
    logger.error("Failed to initialize build error handling")
    success = false
  end

  if success then
    M._setup_event_handlers()
    M._setup_commands()
    build_initialized = true
    logger.info("Build system initialized successfully")
  end

  return success
end

--- Setup event handlers for build integration
function M._setup_event_handlers()
  -- Solution events
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M.on_solution_loaded(data)
  end)

  events.subscribe(events.EVENTS.SOLUTION_UNLOADED, function(data)
    M.on_solution_unloaded(data)
  end)

  -- Project events
  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M.on_project_changed(data)
  end)

  -- File events for incremental builds
  events.subscribe(events.EVENTS.FILE_MODIFIED, function(data)
    M.on_file_modified(data)
  end)
end

--- Setup user commands for build operations
function M._setup_commands()
  -- Build commands
  vim.api.nvim_create_user_command('DotnetBuild', function(opts)
    M.build_solution(opts.args)
  end, { 
    desc = 'Build .NET solution or project',
    nargs = '?',
    complete = M._complete_build_targets
  })

  vim.api.nvim_create_user_command('DotnetRebuild', function(opts)
    M.rebuild_solution(opts.args)
  end, { 
    desc = 'Rebuild .NET solution or project',
    nargs = '?',
    complete = M._complete_build_targets
  })

  vim.api.nvim_create_user_command('DotnetClean', function(opts)
    M.clean_solution(opts.args)
  end, { 
    desc = 'Clean .NET solution or project',
    nargs = '?',
    complete = M._complete_build_targets
  })

  vim.api.nvim_create_user_command('DotnetRestore', function(opts)
    M.restore_packages(opts.args)
  end, { 
    desc = 'Restore NuGet packages',
    nargs = '?',
    complete = M._complete_build_targets
  })

  -- Build status commands
  vim.api.nvim_create_user_command('DotnetBuildStatus', function()
    M.show_build_status()
  end, { desc = 'Show current build status' })

  vim.api.nvim_create_user_command('DotnetBuildCancel', function()
    M.cancel_all_builds()
  end, { desc = 'Cancel all running builds' })
end

--- Complete build targets for commands
--- @param arg_lead string Current argument
--- @param cmd_line string Full command line
--- @param cursor_pos number Cursor position
--- @return table Completion options
function M._complete_build_targets(arg_lead, cmd_line, cursor_pos)
  local targets = {}
  
  -- Add solution file if available
  local solution_parser = require('dotnet-plugin.solution.parser')
  local current_solution = solution_parser.get_current_solution()
  if current_solution then
    table.insert(targets, vim.fn.fnamemodify(current_solution.path, ":t"))
  end
  
  -- Add project files
  local project_parser = require('dotnet-plugin.project.parser')
  local projects = project_parser.get_all_projects()
  for _, project in ipairs(projects) do
    table.insert(targets, vim.fn.fnamemodify(project.path, ":t"))
  end
  
  -- Filter by current input
  if arg_lead and arg_lead ~= "" then
    targets = vim.tbl_filter(function(target)
      return vim.startswith(target, arg_lead)
    end, targets)
  end
  
  return targets
end

--- Handle solution loaded event
--- @param data table Solution data
function M.on_solution_loaded(data)
  logger.debug("Build system: Solution loaded", { path = data.path })
  
  -- Auto-restore packages if configured
  local build_config = config.get_value("build") or {}
  if build_config.auto_restore_on_load then
    M.restore_packages(data.path)
  end
end

--- Handle solution unloaded event
--- @param data table Solution data
function M.on_solution_unloaded(data)
  logger.debug("Build system: Solution unloaded", { path = data.path })
  
  -- Cancel any running builds for this solution
  M.cancel_builds_for_solution(data.path)
end

--- Handle project changed event
--- @param data table Project data
function M.on_project_changed(data)
  logger.debug("Build system: Project changed", { path = data.path })
  
  -- Trigger incremental build if configured
  local build_config = config.get_value("build") or {}
  if build_config.auto_build_on_change then
    M.build_project(data.path)
  end
end

--- Handle file modified event
--- @param data table File data
function M.on_file_modified(data)
  -- Check if it's a build-relevant file
  local file_ext = vim.fn.fnamemodify(data.file, ":e")
  local build_extensions = { "cs", "fs", "vb", "csproj", "fsproj", "vbproj" }
  
  if vim.tbl_contains(build_extensions, file_ext) then
    logger.debug("Build system: Build-relevant file modified", { file = data.file })
    
    -- Trigger incremental build if configured
    local build_config = config.get_value("build") or {}
    if build_config.auto_build_on_save then
      M.build_current_project()
    end
  end
end

--- Build solution or project
--- @param target string|nil Target to build (solution/project path)
--- @return number|nil Build ID
function M.build_solution(target)
  target = target or M._get_default_build_target()
  if not target then
    logger.warn("No build target specified and no solution/project found")
    return nil
  end
  
  build_counter = build_counter + 1
  local build_id = build_counter
  
  logger.info("Starting build", { target = target, build_id = build_id })
  
  -- Emit build started event
  events.emit(events.EVENTS.BUILD_STARTED, {
    build_id = build_id,
    target = target,
    operation = "build"
  })
  
  -- Start build process
  local build_result = msbuild.build(target, {
    build_id = build_id,
    on_progress = function(progress_data)
      progress.update_progress(build_id, progress_data)
    end,
    on_error = function(error_data)
      errors.handle_build_error(build_id, error_data)
    end,
    on_complete = function(result)
      M._on_build_complete(build_id, result)
    end
  })
  
  if build_result then
    active_builds[build_id] = {
      id = build_id,
      target = target,
      operation = "build",
      start_time = os.time(),
      process_id = build_result.process_id
    }
  end
  
  return build_id
end

--- Rebuild solution or project
--- @param target string|nil Target to rebuild
--- @return number|nil Build ID
function M.rebuild_solution(target)
  target = target or M._get_default_build_target()
  if not target then
    logger.warn("No rebuild target specified and no solution/project found")
    return nil
  end
  
  build_counter = build_counter + 1
  local build_id = build_counter
  
  logger.info("Starting rebuild", { target = target, build_id = build_id })
  
  -- Emit build started event
  events.emit(events.EVENTS.BUILD_STARTED, {
    build_id = build_id,
    target = target,
    operation = "rebuild"
  })
  
  -- Start rebuild process
  local build_result = msbuild.rebuild(target, {
    build_id = build_id,
    on_progress = function(progress_data)
      progress.update_progress(build_id, progress_data)
    end,
    on_error = function(error_data)
      errors.handle_build_error(build_id, error_data)
    end,
    on_complete = function(result)
      M._on_build_complete(build_id, result)
    end
  })
  
  if build_result then
    active_builds[build_id] = {
      id = build_id,
      target = target,
      operation = "rebuild",
      start_time = os.time(),
      process_id = build_result.process_id
    }
  end
  
  return build_id
end

--- Clean solution or project
--- @param target string|nil Target to clean
--- @return number|nil Build ID
function M.clean_solution(target)
  target = target or M._get_default_build_target()
  if not target then
    logger.warn("No clean target specified and no solution/project found")
    return nil
  end
  
  build_counter = build_counter + 1
  local build_id = build_counter
  
  logger.info("Starting clean", { target = target, build_id = build_id })
  
  -- Start clean process
  local build_result = msbuild.clean(target, {
    build_id = build_id,
    on_complete = function(result)
      M._on_build_complete(build_id, result)
    end
  })
  
  if build_result then
    active_builds[build_id] = {
      id = build_id,
      target = target,
      operation = "clean",
      start_time = os.time(),
      process_id = build_result.process_id
    }
  end
  
  return build_id
end

--- Restore NuGet packages
--- @param target string|nil Target to restore packages for
--- @return number|nil Build ID
function M.restore_packages(target)
  target = target or M._get_default_build_target()
  if not target then
    logger.warn("No restore target specified and no solution/project found")
    return nil
  end
  
  build_counter = build_counter + 1
  local build_id = build_counter
  
  logger.info("Starting package restore", { target = target, build_id = build_id })
  
  -- Start restore process
  local build_result = msbuild.restore(target, {
    build_id = build_id,
    on_complete = function(result)
      M._on_build_complete(build_id, result)
    end
  })
  
  if build_result then
    active_builds[build_id] = {
      id = build_id,
      target = target,
      operation = "restore",
      start_time = os.time(),
      process_id = build_result.process_id
    }
  end
  
  return build_id
end

--- Build current project
--- @return number|nil Build ID
function M.build_current_project()
  local current_file = vim.fn.expand('%:p')
  local project_parser = require('dotnet-plugin.project.parser')
  local project = project_parser.find_project_for_file(current_file)
  
  if project then
    return M.build_solution(project.path)
  else
    logger.warn("No project found for current file")
    return nil
  end
end

--- Get default build target
--- @return string|nil Default target path
function M._get_default_build_target()
  -- Try to find solution first
  local solution_parser = require('dotnet-plugin.solution.parser')
  local current_solution = solution_parser.get_current_solution()
  if current_solution then
    return current_solution.path
  end
  
  -- Fallback to current project
  local current_file = vim.fn.expand('%:p')
  local project_parser = require('dotnet-plugin.project.parser')
  local project = project_parser.find_project_for_file(current_file)
  if project then
    return project.path
  end
  
  return nil
end

--- Handle build completion
--- @param build_id number Build ID
--- @param result table Build result
function M._on_build_complete(build_id, result)
  local build_info = active_builds[build_id]
  if not build_info then
    return
  end
  
  build_info.end_time = os.time()
  build_info.duration = build_info.end_time - build_info.start_time
  build_info.result = result
  
  if result.success then
    logger.info("Build completed successfully", { 
      build_id = build_id, 
      duration = build_info.duration 
    })
    
    events.emit(events.EVENTS.BUILD_COMPLETED, {
      build_id = build_id,
      target = build_info.target,
      operation = build_info.operation,
      duration = build_info.duration,
      result = result
    })
  else
    logger.error("Build failed", { 
      build_id = build_id, 
      error = result.error 
    })
    
    events.emit(events.EVENTS.BUILD_FAILED, {
      build_id = build_id,
      target = build_info.target,
      operation = build_info.operation,
      duration = build_info.duration,
      error = result.error,
      result = result
    })
  end
  
  -- Remove from active builds
  active_builds[build_id] = nil
end

--- Show build status
function M.show_build_status()
  local status_lines = {}
  
  if vim.tbl_isempty(active_builds) then
    table.insert(status_lines, "No active builds")
  else
    table.insert(status_lines, "Active builds:")
    for build_id, build_info in pairs(active_builds) do
      local duration = os.time() - build_info.start_time
      table.insert(status_lines, string.format(
        "  Build %d: %s %s (%ds)",
        build_id,
        build_info.operation,
        vim.fn.fnamemodify(build_info.target, ":t"),
        duration
      ))
    end
  end
  
  vim.notify(table.concat(status_lines, "\n"), vim.log.levels.INFO)
end

--- Cancel all builds
function M.cancel_all_builds()
  local cancelled_count = 0
  
  for build_id, build_info in pairs(active_builds) do
    if msbuild.cancel_build(build_id) then
      cancelled_count = cancelled_count + 1
      active_builds[build_id] = nil
    end
  end
  
  if cancelled_count > 0 then
    logger.info("Cancelled builds", { count = cancelled_count })
    vim.notify(string.format("Cancelled %d build(s)", cancelled_count), vim.log.levels.INFO)
  else
    vim.notify("No builds to cancel", vim.log.levels.INFO)
  end
end

--- Cancel builds for specific solution
--- @param solution_path string Solution path
function M.cancel_builds_for_solution(solution_path)
  local cancelled_count = 0
  
  for build_id, build_info in pairs(active_builds) do
    if build_info.target == solution_path then
      if msbuild.cancel_build(build_id) then
        cancelled_count = cancelled_count + 1
        active_builds[build_id] = nil
      end
    end
  end
  
  if cancelled_count > 0 then
    logger.info("Cancelled solution builds", { 
      solution = solution_path, 
      count = cancelled_count 
    })
  end
end

--- Get build system status
--- @return table Build system status
function M.get_status()
  return {
    initialized = build_initialized,
    active_builds = vim.deepcopy(active_builds),
    build_counter = build_counter
  }
end

--- Shutdown build system
function M.shutdown()
  if build_initialized then
    -- Cancel all active builds
    M.cancel_all_builds()
    
    -- Shutdown components
    errors.shutdown()
    progress.shutdown()
    msbuild.shutdown()
    
    active_builds = {}
    build_initialized = false
    logger.info("Build system shutdown")
  end
end

return M
