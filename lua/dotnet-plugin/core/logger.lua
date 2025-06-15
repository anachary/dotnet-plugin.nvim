-- Logging system for dotnet-plugin.nvim
-- Provides multiple log levels with file and buffer output

local M = {}

-- Log levels
M.LEVELS = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4
}

-- Level names
local LEVEL_NAMES = {
  [M.LEVELS.DEBUG] = "DEBUG",
  [M.LEVELS.INFO] = "INFO",
  [M.LEVELS.WARN] = "WARN",
  [M.LEVELS.ERROR] = "ERROR"
}

-- Current configuration
local config = {
  level = M.LEVELS.INFO,
  file_enabled = true,
  buffer_enabled = false,
  file_path = nil
}

-- Log buffer
local log_buffer = nil

--- Setup the logging system
--- @param opts table Logging configuration
function M.setup(opts)
  opts = opts or {}
  
  -- Parse log level
  if type(opts.level) == "string" then
    local level_map = {
      debug = M.LEVELS.DEBUG,
      info = M.LEVELS.INFO,
      warn = M.LEVELS.WARN,
      error = M.LEVELS.ERROR
    }
    config.level = level_map[opts.level:lower()] or M.LEVELS.INFO
  elseif type(opts.level) == "number" then
    config.level = opts.level
  end
  
  config.file_enabled = opts.file_enabled ~= false
  config.buffer_enabled = opts.buffer_enabled == true
  
  if type(opts.file_path) == "function" then
    config.file_path = opts.file_path()
  else
    config.file_path = opts.file_path or (vim.fn.stdpath("cache") .. "/dotnet-plugin/dotnet-plugin.log")
  end
  
  -- Ensure log directory exists
  if config.file_enabled then
    local log_dir = vim.fn.fnamemodify(config.file_path, ":h")
    vim.fn.mkdir(log_dir, "p")
  end
  
  -- Create log buffer if needed
  if config.buffer_enabled then
    M.create_log_buffer()
  end
end

--- Create a log buffer
function M.create_log_buffer()
  if log_buffer and vim.api.nvim_buf_is_valid(log_buffer) then
    return log_buffer
  end
  
  log_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(log_buffer, "dotnet-plugin://log")
  vim.api.nvim_buf_set_option(log_buffer, "buftype", "nofile")
  vim.api.nvim_buf_set_option(log_buffer, "swapfile", false)
  vim.api.nvim_buf_set_option(log_buffer, "filetype", "log")
  
  return log_buffer
end

--- Format a log message
--- @param level number Log level
--- @param message string Log message
--- @param context table|nil Additional context
--- @return string Formatted message
local function format_message(level, message, context)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local level_name = LEVEL_NAMES[level] or "UNKNOWN"
  
  local formatted = string.format("[%s] %s: %s", timestamp, level_name, message)
  
  if context then
    local context_str = vim.inspect(context, { indent = "  " })
    formatted = formatted .. "\n" .. context_str
  end
  
  return formatted
end

--- Write to log file
--- @param message string Formatted message
local function write_to_file(message)
  if not config.file_enabled or not config.file_path then
    return
  end
  
  local file = io.open(config.file_path, "a")
  if file then
    file:write(message .. "\n")
    file:close()
  end
end

--- Write to log buffer
--- @param message string Formatted message
local function write_to_buffer(message)
  if not config.buffer_enabled then
    return
  end
  
  if not log_buffer or not vim.api.nvim_buf_is_valid(log_buffer) then
    M.create_log_buffer()
  end
  
  local lines = vim.split(message, "\n")
  vim.api.nvim_buf_set_lines(log_buffer, -1, -1, false, lines)
  
  -- Keep buffer size reasonable (max 1000 lines)
  local line_count = vim.api.nvim_buf_line_count(log_buffer)
  if line_count > 1000 then
    vim.api.nvim_buf_set_lines(log_buffer, 0, line_count - 1000, false, {})
  end
end

--- Log a message
--- @param level number Log level
--- @param message string Log message
--- @param context table|nil Additional context
local function log(level, message, context)
  if level < config.level then
    return
  end
  
  local formatted = format_message(level, message, context)
  
  write_to_file(formatted)
  write_to_buffer(formatted)
  
  -- Also output to Neovim's message system for errors and warnings
  if level >= M.LEVELS.WARN then
    local vim_level = level == M.LEVELS.WARN and vim.log.levels.WARN or vim.log.levels.ERROR
    vim.notify(message, vim_level)
  end
end

--- Log debug message
--- @param message string Log message
--- @param context table|nil Additional context
function M.debug(message, context)
  log(M.LEVELS.DEBUG, message, context)
end

--- Log info message
--- @param message string Log message
--- @param context table|nil Additional context
function M.info(message, context)
  log(M.LEVELS.INFO, message, context)
end

--- Log warning message
--- @param message string Log message
--- @param context table|nil Additional context
function M.warn(message, context)
  log(M.LEVELS.WARN, message, context)
end

--- Log error message
--- @param message string Log message
--- @param context table|nil Additional context
function M.error(message, context)
  log(M.LEVELS.ERROR, message, context)
end

--- Get current log level
--- @return number Current log level
function M.get_level()
  return config.level
end

--- Set log level
--- @param level number|string New log level
function M.set_level(level)
  if type(level) == "string" then
    local level_map = {
      debug = M.LEVELS.DEBUG,
      info = M.LEVELS.INFO,
      warn = M.LEVELS.WARN,
      error = M.LEVELS.ERROR
    }
    config.level = level_map[level:lower()] or M.LEVELS.INFO
  elseif type(level) == "number" then
    config.level = level
  end
end

--- Get log buffer
--- @return number|nil Log buffer number
function M.get_buffer()
  return log_buffer
end

--- Open log buffer in a window
function M.open_log()
  if not log_buffer or not vim.api.nvim_buf_is_valid(log_buffer) then
    M.create_log_buffer()
  end
  
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, log_buffer)
  vim.api.nvim_win_set_height(0, 15)
end

--- Clear log file and buffer
function M.clear()
  -- Clear file
  if config.file_enabled and config.file_path then
    local file = io.open(config.file_path, "w")
    if file then
      file:close()
    end
  end
  
  -- Clear buffer
  if log_buffer and vim.api.nvim_buf_is_valid(log_buffer) then
    vim.api.nvim_buf_set_lines(log_buffer, 0, -1, false, {})
  end
end

return M
