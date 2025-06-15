-- Notification system for dotnet-plugin.nvim
-- Provides user feedback and progress indicators

local M = {}

local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')

-- Notification state
local notifications_initialized = false
local notification_history = {}
local max_history = 50

-- Notification levels
local LEVELS = {
  ERROR = vim.log.levels.ERROR,
  WARN = vim.log.levels.WARN,
  INFO = vim.log.levels.INFO,
  DEBUG = vim.log.levels.DEBUG
}

-- Notification icons
local ICONS = {
  [LEVELS.ERROR] = "󰅚",
  [LEVELS.WARN] = "󰀪",
  [LEVELS.INFO] = "󰋽",
  [LEVELS.DEBUG] = "󰌃",
  success = "󰄬",
  build = "󰑮",
  lsp = "󰌘"
}

--- Setup notification system
--- @return boolean success True if notifications were initialized successfully
function M.setup()
  if notifications_initialized then
    return true
  end

  local notifications_config = config.get_value("ui.notifications") or {}
  
  if not notifications_config.enabled then
    logger.debug("Notification system disabled in configuration")
    return true
  end

  logger.debug("Initializing notification system")

  -- Setup notification backend
  M._setup_backend()
  
  notifications_initialized = true
  logger.debug("Notification system initialized")
  
  return true
end

--- Setup notification backend
function M._setup_backend()
  local notifications_config = config.get_value("ui.notifications") or {}
  local backend = notifications_config.backend or "auto"
  
  if backend == "auto" then
    -- Try to detect and use available notification plugins
    if M._try_setup_nvim_notify() then
      return
    elseif M._try_setup_fidget() then
      return
    else
      -- Fallback to vim.notify
      M._setup_vim_notify()
    end
  elseif backend == "nvim-notify" then
    M._try_setup_nvim_notify()
  elseif backend == "fidget" then
    M._try_setup_fidget()
  elseif backend == "vim" then
    M._setup_vim_notify()
  end
end

--- Try to setup nvim-notify
--- @return boolean success True if nvim-notify was setup successfully
function M._try_setup_nvim_notify()
  local ok, notify = pcall(require, 'notify')
  if ok then
    -- Configure nvim-notify for dotnet-plugin
    local notifications_config = config.get_value("ui.notifications") or {}
    
    M._notify_func = function(message, level, opts)
      opts = opts or {}
      opts.title = opts.title or ".NET Plugin"
      opts.icon = opts.icon or ICONS[level]
      
      -- Add timeout based on level
      if not opts.timeout then
        if level == LEVELS.ERROR then
          opts.timeout = notifications_config.error_timeout or 5000
        elseif level == LEVELS.WARN then
          opts.timeout = notifications_config.warn_timeout or 3000
        else
          opts.timeout = notifications_config.info_timeout or 2000
        end
      end
      
      notify(message, level, opts)
    end
    
    logger.debug("Using nvim-notify for notifications")
    return true
  end
  
  return false
end

--- Try to setup fidget.nvim
--- @return boolean success True if fidget was setup successfully
function M._try_setup_fidget()
  local ok, fidget = pcall(require, 'fidget')
  if ok then
    M._notify_func = function(message, level, opts)
      opts = opts or {}
      
      if level == LEVELS.ERROR then
        fidget.notify(message, vim.log.levels.ERROR, opts)
      elseif level == LEVELS.WARN then
        fidget.notify(message, vim.log.levels.WARN, opts)
      else
        fidget.notify(message, vim.log.levels.INFO, opts)
      end
    end
    
    logger.debug("Using fidget.nvim for notifications")
    return true
  end
  
  return false
end

--- Setup vim.notify fallback
function M._setup_vim_notify()
  M._notify_func = function(message, level, opts)
    opts = opts or {}
    local title = opts.title or ".NET Plugin"
    local full_message = string.format("[%s] %s", title, message)
    vim.notify(full_message, level)
  end
  
  logger.debug("Using vim.notify for notifications")
end

--- Show error notification
--- @param message string Error message
--- @param opts table|nil Notification options
function M.show_error(message, opts)
  if not notifications_initialized then
    return
  end
  
  opts = opts or {}
  opts.icon = opts.icon or ICONS[LEVELS.ERROR]
  
  M._notify_func(message, LEVELS.ERROR, opts)
  M._add_to_history("error", message, opts)
  
  logger.error("Notification: " .. message)
end

--- Show warning notification
--- @param message string Warning message
--- @param opts table|nil Notification options
function M.show_warning(message, opts)
  if not notifications_initialized then
    return
  end
  
  opts = opts or {}
  opts.icon = opts.icon or ICONS[LEVELS.WARN]
  
  M._notify_func(message, LEVELS.WARN, opts)
  M._add_to_history("warning", message, opts)
  
  logger.warn("Notification: " .. message)
end

--- Show info notification
--- @param message string Info message
--- @param opts table|nil Notification options
function M.show_info(message, opts)
  if not notifications_initialized then
    return
  end
  
  opts = opts or {}
  opts.icon = opts.icon or ICONS[LEVELS.INFO]
  
  M._notify_func(message, LEVELS.INFO, opts)
  M._add_to_history("info", message, opts)
  
  logger.info("Notification: " .. message)
end

--- Show success notification
--- @param message string Success message
--- @param opts table|nil Notification options
function M.show_success(message, opts)
  if not notifications_initialized then
    return
  end
  
  opts = opts or {}
  opts.icon = opts.icon or ICONS.success
  
  M._notify_func(message, LEVELS.INFO, opts)
  M._add_to_history("success", message, opts)
  
  logger.info("Success notification: " .. message)
end

--- Show build notification
--- @param message string Build message
--- @param opts table|nil Notification options
function M.show_build(message, opts)
  if not notifications_initialized then
    return
  end
  
  opts = opts or {}
  opts.icon = opts.icon or ICONS.build
  opts.title = opts.title or ".NET Build"
  
  M._notify_func(message, LEVELS.INFO, opts)
  M._add_to_history("build", message, opts)
  
  logger.info("Build notification: " .. message)
end

--- Show LSP notification
--- @param message string LSP message
--- @param level string|nil Notification level (error, warn, info)
--- @param opts table|nil Notification options
function M.show_lsp(message, level, opts)
  if not notifications_initialized then
    return
  end
  
  level = level or "info"
  opts = opts or {}
  opts.icon = opts.icon or ICONS.lsp
  opts.title = opts.title or ".NET LSP"
  
  local log_level = LEVELS.INFO
  if level == "error" then
    log_level = LEVELS.ERROR
  elseif level == "warn" then
    log_level = LEVELS.WARN
  end
  
  M._notify_func(message, log_level, opts)
  M._add_to_history("lsp", message, opts)
  
  logger.log(log_level, "LSP notification: " .. message)
end

--- Show progress notification
--- @param message string Progress message
--- @param progress number|nil Progress percentage (0-100)
--- @param opts table|nil Notification options
function M.show_progress(message, progress, opts)
  if not notifications_initialized then
    return
  end
  
  opts = opts or {}
  
  local full_message = message
  if progress then
    full_message = string.format("%s (%d%%)", message, progress)
  end
  
  opts.icon = opts.icon or ICONS[LEVELS.INFO]
  opts.replace = opts.replace or true -- Replace previous progress notifications
  
  M._notify_func(full_message, LEVELS.INFO, opts)
  M._add_to_history("progress", full_message, opts)
end

--- Add notification to history
--- @param type string Notification type
--- @param message string Notification message
--- @param opts table Notification options
function M._add_to_history(type, message, opts)
  local entry = {
    type = type,
    message = message,
    timestamp = os.time(),
    opts = opts
  }
  
  table.insert(notification_history, entry)
  
  -- Trim history if too long
  if #notification_history > max_history then
    table.remove(notification_history, 1)
  end
end

--- Get notification history
--- @param count number|nil Number of recent notifications to return
--- @return table Notification history
function M.get_history(count)
  count = count or #notification_history
  local start_index = math.max(1, #notification_history - count + 1)
  
  local result = {}
  for i = start_index, #notification_history do
    table.insert(result, notification_history[i])
  end
  
  return result
end

--- Clear notification history
function M.clear_history()
  notification_history = {}
  logger.debug("Notification history cleared")
end

--- Get notification statistics
--- @return table Notification statistics
function M.get_stats()
  local stats = {
    total = #notification_history,
    by_type = {}
  }
  
  for _, entry in ipairs(notification_history) do
    stats.by_type[entry.type] = (stats.by_type[entry.type] or 0) + 1
  end
  
  return stats
end

--- Check if notifications are enabled
--- @return boolean True if notifications are enabled
function M.is_enabled()
  return notifications_initialized
end

--- Shutdown notification system
function M.shutdown()
  if notifications_initialized then
    M._notify_func = nil
    notification_history = {}
    notifications_initialized = false
    logger.debug("Notification system shutdown")
  end
end

return M
