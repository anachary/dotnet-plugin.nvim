-- Window Management Module for Enhanced Solution Explorer
-- Single Responsibility: Manages window creation, configuration, and lifecycle

local M = {}

local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')

-- Window state
local window_state = {
  buffer = nil,
  window = nil,
  config = {}
}

--- Initialize window manager
--- @param opts table|nil Configuration options
--- @return boolean success
function M.setup(opts)
  window_state.config = vim.tbl_deep_extend("force", {
    width = 35,
    height = vim.o.lines - 10,
    position = "left",
    border = "rounded",
    title = " .NET Enhanced Explorer ",
    title_pos = "center"
  }, opts or {})
  
  logger.debug("Window manager initialized")
  return true
end

--- Create explorer buffer with proper configuration
--- @return number buffer_id
function M.create_buffer()
  if window_state.buffer and vim.api.nvim_buf_is_valid(window_state.buffer) then
    return window_state.buffer
  end
  
  window_state.buffer = vim.api.nvim_create_buf(false, true)
  
  -- Configure buffer options
  local buffer_options = {
    buftype = 'nofile',
    swapfile = false,
    bufhidden = 'wipe',
    filetype = 'dotnet-enhanced-explorer'
  }
  
  for option, value in pairs(buffer_options) do
    vim.api.nvim_buf_set_option(window_state.buffer, option, value)
  end
  
  vim.api.nvim_buf_set_name(window_state.buffer, window_state.config.title)
  
  logger.debug("Explorer buffer created", { buffer_id = window_state.buffer })
  return window_state.buffer
end

--- Create explorer window with floating configuration
--- @return number window_id
function M.create_window()
  if window_state.window and vim.api.nvim_win_is_valid(window_state.window) then
    return window_state.window
  end
  
  local buffer = M.create_buffer()
  local win_config = M._build_window_config()
  
  window_state.window = vim.api.nvim_open_win(buffer, true, win_config)
  
  -- Configure window options
  local window_options = {
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    wrap = false,
    cursorline = true,
    foldcolumn = '0'
  }
  
  for option, value in pairs(window_options) do
    vim.api.nvim_win_set_option(window_state.window, option, value)
  end
  
  logger.debug("Explorer window created", { window_id = window_state.window })
  return window_state.window
end

--- Build window configuration based on settings
--- @return table window_config
function M._build_window_config()
  local cfg = window_state.config
  
  return {
    relative = 'editor',
    width = cfg.width,
    height = cfg.height,
    col = cfg.position == "right" and (vim.o.columns - cfg.width - 2) or 1,
    row = 1,
    style = 'minimal',
    border = cfg.border,
    title = cfg.title,
    title_pos = cfg.title_pos
  }
end

--- Check if window is currently open
--- @return boolean is_open
function M.is_open()
  return window_state.window and vim.api.nvim_win_is_valid(window_state.window)
end

--- Get current buffer ID
--- @return number|nil buffer_id
function M.get_buffer()
  return window_state.buffer
end

--- Get current window ID
--- @return number|nil window_id
function M.get_window()
  return window_state.window
end

--- Close the explorer window
function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(window_state.window, false)
    window_state.window = nil
    logger.debug("Explorer window closed")
  end
end

--- Focus the explorer window
function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(window_state.window)
  end
end

--- Cleanup window resources
function M.cleanup()
  M.close()
  
  if window_state.buffer and vim.api.nvim_buf_is_valid(window_state.buffer) then
    vim.api.nvim_buf_delete(window_state.buffer, { force = true })
    window_state.buffer = nil
  end
  
  logger.debug("Window manager cleaned up")
end

return M
