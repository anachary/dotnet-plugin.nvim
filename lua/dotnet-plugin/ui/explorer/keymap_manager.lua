-- Keymap Manager Module for Enhanced Solution Explorer
-- Single Responsibility: Manages all keyboard shortcuts and interactions

local M = {}

local logger = require('dotnet-plugin.core.logger')

-- Keymap state
local keymap_state = {
  buffer = nil,
  keymaps = {},
  callbacks = {}
}

-- Default keymap configuration
local DEFAULT_KEYMAPS = {
  -- Navigation
  ["<CR>"] = "open_item",
  ["o"] = "open_item", 
  ["<2-LeftMouse>"] = "open_item",
  
  -- Tree operations
  ["<Tab>"] = "toggle_node",
  ["<Space>"] = "toggle_node",
  ["za"] = "toggle_node",
  
  -- File operations
  ["a"] = "create_file",
  ["A"] = "create_folder",
  ["p"] = "create_project",
  ["r"] = "rename_item",
  ["d"] = "delete_item",
  ["c"] = "copy_item",
  ["m"] = "move_item",
  
  -- Project operations
  ["R"] = "add_reference",
  ["P"] = "manage_packages",
  
  -- Search and filter
  ["/"] = "filter_items",
  ["f"] = "search_files",
  ["F"] = "clear_filter",
  
  -- View options
  ["H"] = "toggle_hidden_files",
  ["I"] = "show_file_info",
  
  -- Context menu
  ["<RightMouse>"] = "show_context_menu",
  ["C"] = "show_context_menu",
  
  -- Refresh
  ["<F5>"] = "refresh_all",
  ["g"] = "refresh_current",
  
  -- Window operations
  ["q"] = "close_explorer",
  ["<Esc>"] = "close_explorer",
  
  -- Help
  ["?"] = "show_help"
}

--- Initialize keymap manager
--- @param buffer number Buffer ID
--- @param callbacks table Callback functions
--- @param custom_keymaps table|nil Custom keymap overrides
--- @return boolean success
function M.setup(buffer, callbacks, custom_keymaps)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    logger.error("Invalid buffer for keymap setup")
    return false
  end
  
  keymap_state.buffer = buffer
  keymap_state.callbacks = callbacks or {}
  
  -- Merge custom keymaps with defaults
  local keymaps = vim.tbl_deep_extend("force", DEFAULT_KEYMAPS, custom_keymaps or {})
  
  -- Register all keymaps
  for key, action in pairs(keymaps) do
    M._register_keymap(key, action)
  end
  
  logger.debug("Keymap manager initialized", { 
    buffer = buffer, 
    keymaps_count = vim.tbl_count(keymaps) 
  })
  
  return true
end

--- Register a single keymap
--- @param key string Key combination
--- @param action string Action name
function M._register_keymap(key, action)
  local callback = keymap_state.callbacks[action]
  if not callback then
    logger.warn("No callback found for action: " .. action)
    return
  end
  
  local opts = { 
    buffer = keymap_state.buffer, 
    silent = true,
    desc = M._get_keymap_description(action)
  }
  
  vim.keymap.set('n', key, function()
    M._safe_callback(action, callback)
  end, opts)
  
  -- Store keymap info
  keymap_state.keymaps[key] = {
    action = action,
    description = opts.desc
  }
end

--- Safely execute callback with error handling
--- @param action string Action name
--- @param callback function Callback function
function M._safe_callback(action, callback)
  local success, error_msg = pcall(callback)
  if not success then
    logger.error("Keymap callback failed", { 
      action = action, 
      error = error_msg 
    })
    
    -- Show user-friendly error
    vim.notify("Action failed: " .. action, vim.log.levels.ERROR)
  end
end

--- Get description for keymap action
--- @param action string Action name
--- @return string description
function M._get_keymap_description(action)
  local descriptions = {
    open_item = "Open file/toggle folder",
    toggle_node = "Toggle node expansion",
    create_file = "Create new file",
    create_folder = "Create new folder",
    create_project = "Create new project",
    rename_item = "Rename item",
    delete_item = "Delete item",
    copy_item = "Copy item",
    move_item = "Move item",
    add_reference = "Add project reference",
    manage_packages = "Manage NuGet packages",
    filter_items = "Filter items",
    search_files = "Search files",
    clear_filter = "Clear filter",
    toggle_hidden_files = "Toggle hidden files",
    show_file_info = "Show file information",
    show_context_menu = "Show context menu",
    refresh_all = "Refresh all",
    refresh_current = "Refresh current",
    close_explorer = "Close explorer",
    show_help = "Show help"
  }
  
  return descriptions[action] or action
end

--- Get keymap help text
--- @return table help_lines
function M.get_help_text()
  local help_lines = {
    "Enhanced Solution Explorer - Keyboard Shortcuts",
    "",
    "Navigation:",
    "  <CR>, o     - Open file/toggle folder",
    "  <Tab>       - Toggle node expansion",
    "",
    "File Operations:",
    "  a           - Create file",
    "  A           - Create folder", 
    "  p           - Create project",
    "  r           - Rename",
    "  d           - Delete",
    "  c           - Copy",
    "  m           - Move",
    "",
    "Project Operations:",
    "  R           - Add reference",
    "  P           - Manage packages",
    "",
    "Search & Filter:",
    "  /           - Filter",
    "  f           - Search files",
    "  F           - Clear filter",
    "",
    "View Options:",
    "  H           - Toggle hidden files",
    "  I           - Show file info",
    "",
    "Other:",
    "  <F5>        - Refresh all",
    "  g           - Refresh current",
    "  C           - Context menu",
    "  ?           - Show this help",
    "  q, <Esc>    - Close explorer"
  }
  
  return help_lines
end

--- Cleanup keymap manager
function M.cleanup()
  if keymap_state.buffer and vim.api.nvim_buf_is_valid(keymap_state.buffer) then
    for key, _ in pairs(keymap_state.keymaps) do
      pcall(vim.keymap.del, 'n', key, { buffer = keymap_state.buffer })
    end
  end
  
  keymap_state = {
    buffer = nil,
    keymaps = {},
    callbacks = {}
  }
  
  logger.debug("Keymap manager cleaned up")
end

return M
