-- Build progress tracking for dotnet-plugin.nvim
-- Tracks and reports build progress in real-time

local M = {}

local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

-- Progress state
local progress_initialized = false
local build_progress = {}

--- Setup progress tracking
--- @return boolean success True if progress tracking was initialized successfully
function M.setup()
  if progress_initialized then
    return true
  end

  logger.debug("Initializing build progress tracking")

  progress_initialized = true
  logger.debug("Build progress tracking initialized")
  
  return true
end

--- Update build progress
--- @param build_id number Build ID
--- @param progress_data table Progress information
function M.update_progress(build_id, progress_data)
  if not progress_initialized then
    return
  end
  
  -- Initialize progress tracking for this build if needed
  if not build_progress[build_id] then
    build_progress[build_id] = {
      build_id = build_id,
      start_time = os.time(),
      stages = {},
      current_stage = nil,
      overall_progress = 0,
      projects = {},
      errors = 0,
      warnings = 0
    }
  end
  
  local progress = build_progress[build_id]
  
  -- Update progress based on data type
  if progress_data.type == "project" then
    M._update_project_progress(progress, progress_data)
  elseif progress_data.type == "stage" then
    M._update_stage_progress(progress, progress_data)
  elseif progress_data.type == "completed" then
    M._update_completion_status(progress, progress_data)
  elseif progress_data.type == "error" then
    M._update_error_count(progress, progress_data)
  elseif progress_data.type == "warning" then
    M._update_warning_count(progress, progress_data)
  end
  
  -- Calculate overall progress
  M._calculate_overall_progress(progress)
  
  -- Emit progress event
  events.emit(events.EVENTS.BUILD_PROGRESS, {
    build_id = build_id,
    progress = vim.deepcopy(progress)
  })
  
  -- Show progress notification if configured
  local build_config = config.get_value("build") or {}
  if build_config.show_progress_notifications then
    M._show_progress_notification(progress)
  end
  
  logger.debug("Build progress updated", {
    build_id = build_id,
    overall_progress = progress.overall_progress,
    current_stage = progress.current_stage
  })
end

--- Update project progress
--- @param progress table Progress state
--- @param data table Project progress data
function M._update_project_progress(progress, data)
  progress.projects[data.project] = {
    name = data.project,
    current = data.current,
    total = data.total,
    percentage = data.percentage,
    status = "building"
  }
  
  progress.current_stage = string.format("Building %s (%d/%d)", 
    data.project, data.current, data.total)
end

--- Update stage progress
--- @param progress table Progress state
--- @param data table Stage progress data
function M._update_stage_progress(progress, data)
  progress.stages[data.stage] = {
    name = data.stage,
    status = data.status,
    start_time = data.start_time or os.time(),
    end_time = data.end_time
  }
  
  progress.current_stage = data.stage
end

--- Update completion status
--- @param progress table Progress state
--- @param data table Completion data
function M._update_completion_status(progress, data)
  progress.status = data.status
  progress.end_time = os.time()
  progress.duration = progress.end_time - progress.start_time
  
  if data.status == "success" then
    progress.overall_progress = 100
    progress.current_stage = "Build completed successfully"
  elseif data.status == "failed" then
    progress.current_stage = "Build failed"
  end
end

--- Update error count
--- @param progress table Progress state
--- @param data table Error data
function M._update_error_count(progress, data)
  progress.errors = progress.errors + 1
end

--- Update warning count
--- @param progress table Progress state
--- @param data table Warning data
function M._update_warning_count(progress, data)
  progress.warnings = progress.warnings + 1
end

--- Calculate overall progress percentage
--- @param progress table Progress state
function M._calculate_overall_progress(progress)
  if progress.status == "success" then
    progress.overall_progress = 100
    return
  elseif progress.status == "failed" then
    return
  end
  
  -- Calculate based on project progress
  local total_projects = 0
  local completed_projects = 0
  
  for _, project in pairs(progress.projects) do
    total_projects = total_projects + 1
    if project.percentage then
      completed_projects = completed_projects + (project.percentage / 100)
    end
  end
  
  if total_projects > 0 then
    progress.overall_progress = math.floor((completed_projects / total_projects) * 100)
  else
    -- Fallback to stage-based progress
    local completed_stages = 0
    local total_stages = 0
    
    for _, stage in pairs(progress.stages) do
      total_stages = total_stages + 1
      if stage.status == "completed" then
        completed_stages = completed_stages + 1
      end
    end
    
    if total_stages > 0 then
      progress.overall_progress = math.floor((completed_stages / total_stages) * 100)
    end
  end
end

--- Show progress notification
--- @param progress table Progress state
function M._show_progress_notification(progress)
  local notifications = require('dotnet-plugin.ui.notifications')
  
  if not notifications.is_enabled() then
    return
  end
  
  local message = progress.current_stage or "Building..."
  
  if progress.overall_progress > 0 then
    notifications.show_progress(message, progress.overall_progress, {
      title = ".NET Build",
      replace = true
    })
  else
    notifications.show_build(message, {
      replace = true
    })
  end
end

--- Get progress for build
--- @param build_id number Build ID
--- @return table|nil Progress data
function M.get_progress(build_id)
  return build_progress[build_id] and vim.deepcopy(build_progress[build_id]) or nil
end

--- Get all active build progress
--- @return table All progress data
function M.get_all_progress()
  return vim.deepcopy(build_progress)
end

--- Clear progress for build
--- @param build_id number Build ID
function M.clear_progress(build_id)
  build_progress[build_id] = nil
  logger.debug("Build progress cleared", { build_id = build_id })
end

--- Clear all progress data
function M.clear_all_progress()
  build_progress = {}
  logger.debug("All build progress cleared")
end

--- Get progress summary
--- @param build_id number Build ID
--- @return string Progress summary
function M.get_progress_summary(build_id)
  local progress = build_progress[build_id]
  if not progress then
    return "No progress data"
  end
  
  local lines = {}
  
  -- Overall status
  table.insert(lines, string.format("Build %d: %s", 
    build_id, progress.current_stage or "In progress"))
  
  -- Overall progress
  if progress.overall_progress > 0 then
    table.insert(lines, string.format("Progress: %d%%", progress.overall_progress))
  end
  
  -- Duration
  local duration = progress.duration or (os.time() - progress.start_time)
  table.insert(lines, string.format("Duration: %ds", duration))
  
  -- Error/warning counts
  if progress.errors > 0 or progress.warnings > 0 then
    table.insert(lines, string.format("Errors: %d, Warnings: %d", 
      progress.errors, progress.warnings))
  end
  
  -- Project progress
  if not vim.tbl_isempty(progress.projects) then
    table.insert(lines, "Projects:")
    for _, project in pairs(progress.projects) do
      table.insert(lines, string.format("  %s: %s", 
        project.name, 
        project.percentage and string.format("%d%%", project.percentage) or project.status))
    end
  end
  
  return table.concat(lines, "\n")
end

--- Show progress summary
--- @param build_id number Build ID
function M.show_progress_summary(build_id)
  local summary = M.get_progress_summary(build_id)
  vim.notify(summary, vim.log.levels.INFO)
end

--- Create progress bar string
--- @param percentage number Progress percentage (0-100)
--- @param width number|nil Bar width (default: 20)
--- @return string Progress bar
function M.create_progress_bar(percentage, width)
  width = width or 20
  local filled = math.floor((percentage / 100) * width)
  local empty = width - filled
  
  local bar = string.rep("█", filled) .. string.rep("░", empty)
  return string.format("%s %d%%", bar, percentage)
end

--- Get progress statistics
--- @return table Progress statistics
function M.get_statistics()
  local stats = {
    active_builds = 0,
    completed_builds = 0,
    failed_builds = 0,
    total_errors = 0,
    total_warnings = 0
  }
  
  for _, progress in pairs(build_progress) do
    if progress.status == "success" then
      stats.completed_builds = stats.completed_builds + 1
    elseif progress.status == "failed" then
      stats.failed_builds = stats.failed_builds + 1
    else
      stats.active_builds = stats.active_builds + 1
    end
    
    stats.total_errors = stats.total_errors + progress.errors
    stats.total_warnings = stats.total_warnings + progress.warnings
  end
  
  return stats
end

--- Shutdown progress tracking
function M.shutdown()
  if progress_initialized then
    build_progress = {}
    progress_initialized = false
    logger.debug("Build progress tracking shutdown")
  end
end

return M
