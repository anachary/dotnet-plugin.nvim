-- Build error handling for dotnet-plugin.nvim
-- Parses build errors and integrates with quickfix

local M = {}

local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

-- Error state
local errors_initialized = false
local build_errors = {}
local build_warnings = {}

--- Setup error handling
--- @return boolean success True if error handling was initialized successfully
function M.setup()
  if errors_initialized then
    return true
  end

  logger.debug("Initializing build error handling")

  -- Setup quickfix integration
  M._setup_quickfix_integration()
  
  errors_initialized = true
  logger.debug("Build error handling initialized")
  
  return true
end

--- Setup quickfix integration
function M._setup_quickfix_integration()
  -- Create autocommands for quickfix navigation
  local augroup = vim.api.nvim_create_augroup("DotnetBuildErrors", { clear = true })
  
  -- Auto-open quickfix when errors are added
  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = augroup,
    pattern = "*",
    callback = function()
      local build_config = config.get_value("build") or {}
      if build_config.auto_open_quickfix then
        vim.cmd("copen")
      end
    end
  })
end

--- Handle build error
--- @param build_id number Build ID
--- @param error_data table Error information
function M.handle_build_error(build_id, error_data)
  if not errors_initialized then
    return
  end
  
  -- Initialize error tracking for this build if needed
  if not build_errors[build_id] then
    build_errors[build_id] = {}
  end
  if not build_warnings[build_id] then
    build_warnings[build_id] = {}
  end
  
  -- Categorize error/warning
  if error_data.severity == "error" then
    table.insert(build_errors[build_id], error_data)
    logger.error("Build error", {
      build_id = build_id,
      file = error_data.file,
      line = error_data.line,
      message = error_data.message
    })
  elseif error_data.severity == "warning" then
    table.insert(build_warnings[build_id], error_data)
    logger.warn("Build warning", {
      build_id = build_id,
      file = error_data.file,
      line = error_data.line,
      message = error_data.message
    })
  end
  
  -- Update quickfix list
  M._update_quickfix(build_id)
  
  -- Show notification if configured
  local build_config = config.get_value("build") or {}
  if build_config.show_error_notifications then
    M._show_error_notification(error_data)
  end
  
  -- Emit error event
  events.emit(events.EVENTS.BUILD_PROGRESS, {
    build_id = build_id,
    error = error_data
  })
end

--- Update quickfix list with build errors
--- @param build_id number Build ID
function M._update_quickfix(build_id)
  local qf_items = {}
  
  -- Add errors
  local errors = build_errors[build_id] or {}
  for _, error in ipairs(errors) do
    table.insert(qf_items, M._create_quickfix_item(error, "E"))
  end
  
  -- Add warnings
  local warnings = build_warnings[build_id] or {}
  for _, warning in ipairs(warnings) do
    table.insert(qf_items, M._create_quickfix_item(warning, "W"))
  end
  
  -- Set quickfix list
  if #qf_items > 0 then
    vim.fn.setqflist(qf_items, "r")
    
    -- Set quickfix title
    local title = string.format(".NET Build %d - %d errors, %d warnings", 
      build_id, #errors, #warnings)
    vim.fn.setqflist({}, "a", { title = title })
    
    logger.debug("Quickfix updated", {
      build_id = build_id,
      errors = #errors,
      warnings = #warnings
    })
  end
end

--- Create quickfix item from error data
--- @param error_data table Error information
--- @param type string Error type ("E" for error, "W" for warning)
--- @return table Quickfix item
function M._create_quickfix_item(error_data, type)
  local item = {
    filename = error_data.file or "",
    lnum = error_data.line or 0,
    col = error_data.column or 0,
    text = error_data.message or "",
    type = type
  }
  
  -- Add error code if available
  if error_data.code then
    item.text = string.format("[%s] %s", error_data.code, item.text)
  end
  
  return item
end

--- Show error notification
--- @param error_data table Error information
function M._show_error_notification(error_data)
  local notifications = require('dotnet-plugin.ui.notifications')
  
  if not notifications.is_enabled() then
    return
  end
  
  local message = error_data.message
  if error_data.file then
    local filename = vim.fn.fnamemodify(error_data.file, ":t")
    message = string.format("%s: %s", filename, message)
  end
  
  if error_data.severity == "error" then
    notifications.show_error(message, {
      title = ".NET Build Error"
    })
  elseif error_data.severity == "warning" then
    notifications.show_warning(message, {
      title = ".NET Build Warning"
    })
  end
end

--- Get errors for build
--- @param build_id number Build ID
--- @return table Errors and warnings
function M.get_errors(build_id)
  return {
    errors = build_errors[build_id] and vim.deepcopy(build_errors[build_id]) or {},
    warnings = build_warnings[build_id] and vim.deepcopy(build_warnings[build_id]) or {}
  }
end

--- Get error count for build
--- @param build_id number Build ID
--- @return table Error counts
function M.get_error_count(build_id)
  local errors = build_errors[build_id] or {}
  local warnings = build_warnings[build_id] or {}
  
  return {
    errors = #errors,
    warnings = #warnings,
    total = #errors + #warnings
  }
end

--- Clear errors for build
--- @param build_id number Build ID
function M.clear_errors(build_id)
  build_errors[build_id] = nil
  build_warnings[build_id] = nil
  
  -- Clear quickfix if it was for this build
  local qf_title = vim.fn.getqflist({ title = 0 }).title
  if qf_title and string.match(qf_title, "Build " .. build_id) then
    vim.fn.setqflist({}, "r")
  end
  
  logger.debug("Build errors cleared", { build_id = build_id })
end

--- Clear all errors
function M.clear_all_errors()
  build_errors = {}
  build_warnings = {}
  vim.fn.setqflist({}, "r")
  logger.debug("All build errors cleared")
end

--- Get error summary
--- @param build_id number Build ID
--- @return string Error summary
function M.get_error_summary(build_id)
  local errors = build_errors[build_id] or {}
  local warnings = build_warnings[build_id] or {}
  
  if #errors == 0 and #warnings == 0 then
    return "No errors or warnings"
  end
  
  local lines = {}
  
  -- Summary line
  table.insert(lines, string.format("Build %d: %d errors, %d warnings", 
    build_id, #errors, #warnings))
  
  -- Error details
  if #errors > 0 then
    table.insert(lines, "\nErrors:")
    for i, error in ipairs(errors) do
      if i > 5 then -- Limit to first 5 errors
        table.insert(lines, string.format("  ... and %d more errors", #errors - 5))
        break
      end
      
      local location = ""
      if error.file then
        location = vim.fn.fnamemodify(error.file, ":t")
        if error.line then
          location = location .. ":" .. error.line
        end
        location = location .. " - "
      end
      
      table.insert(lines, string.format("  %s%s", location, error.message))
    end
  end
  
  -- Warning details
  if #warnings > 0 then
    table.insert(lines, "\nWarnings:")
    for i, warning in ipairs(warnings) do
      if i > 3 then -- Limit to first 3 warnings
        table.insert(lines, string.format("  ... and %d more warnings", #warnings - 3))
        break
      end
      
      local location = ""
      if warning.file then
        location = vim.fn.fnamemodify(warning.file, ":t")
        if warning.line then
          location = location .. ":" .. warning.line
        end
        location = location .. " - "
      end
      
      table.insert(lines, string.format("  %s%s", location, warning.message))
    end
  end
  
  return table.concat(lines, "\n")
end

--- Show error summary
--- @param build_id number Build ID
function M.show_error_summary(build_id)
  local summary = M.get_error_summary(build_id)
  vim.notify(summary, vim.log.levels.INFO)
end

--- Jump to first error
--- @param build_id number|nil Build ID (uses current quickfix if nil)
function M.jump_to_first_error(build_id)
  if build_id then
    M._update_quickfix(build_id)
  end
  
  local qf_list = vim.fn.getqflist()
  if #qf_list > 0 then
    -- Find first error (not warning)
    for i, item in ipairs(qf_list) do
      if item.type == "E" then
        vim.cmd("cc " .. i)
        return
      end
    end
    
    -- If no errors, jump to first item
    vim.cmd("cfirst")
  else
    vim.notify("No errors to jump to", vim.log.levels.INFO)
  end
end

--- Jump to next error
function M.jump_to_next_error()
  local ok, _ = pcall(vim.cmd, "cnext")
  if not ok then
    vim.notify("No more errors", vim.log.levels.INFO)
  end
end

--- Jump to previous error
function M.jump_to_previous_error()
  local ok, _ = pcall(vim.cmd, "cprevious")
  if not ok then
    vim.notify("No previous errors", vim.log.levels.INFO)
  end
end

--- Get error statistics
--- @return table Error statistics
function M.get_statistics()
  local stats = {
    total_builds = 0,
    total_errors = 0,
    total_warnings = 0,
    builds_with_errors = 0,
    builds_with_warnings = 0
  }
  
  for build_id, errors in pairs(build_errors) do
    stats.total_builds = stats.total_builds + 1
    stats.total_errors = stats.total_errors + #errors
    
    if #errors > 0 then
      stats.builds_with_errors = stats.builds_with_errors + 1
    end
  end
  
  for build_id, warnings in pairs(build_warnings) do
    stats.total_warnings = stats.total_warnings + #warnings
    
    if #warnings > 0 then
      stats.builds_with_warnings = stats.builds_with_warnings + 1
    end
  end
  
  return stats
end

--- Shutdown error handling
function M.shutdown()
  if errors_initialized then
    build_errors = {}
    build_warnings = {}
    vim.fn.setqflist({}, "r")
    errors_initialized = false
    logger.debug("Build error handling shutdown")
  end
end

return M
