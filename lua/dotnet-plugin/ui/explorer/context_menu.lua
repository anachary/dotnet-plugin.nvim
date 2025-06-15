-- Context Menu Module for Enhanced Solution Explorer
-- Single Responsibility: Manages context-sensitive menus and actions

local M = {}

local logger = require('dotnet-plugin.core.logger')

-- Context menu state
local menu_state = {
  active = false,
  current_node = nil,
  menu_window = nil,
  menu_buffer = nil
}

-- Menu item structure
local MenuItem = {}
MenuItem.__index = MenuItem

function MenuItem:new(label, action, enabled, separator)
  return setmetatable({
    label = label or "",
    action = action,
    enabled = enabled ~= false,
    separator = separator or false
  }, self)
end

--- Initialize context menu manager
--- @param opts table|nil Configuration options
--- @return boolean success
function M.setup(opts)
  logger.debug("Context menu manager initialized")
  return true
end

--- Show context menu for a node
--- @param node table Tree node
--- @param callbacks table Action callbacks
--- @param position table|nil Menu position {row, col}
function M.show_menu(node, callbacks, position)
  if not node or not callbacks then
    logger.error("Invalid parameters for context menu")
    return
  end
  
  -- Close existing menu
  M.close_menu()
  
  menu_state.current_node = node
  menu_state.active = true
  
  -- Build menu items based on node type
  local menu_items = M._build_menu_items(node)
  
  -- Create menu window
  M._create_menu_window(menu_items, callbacks, position)
  
  logger.debug("Context menu shown", { node_type = node.type, node_name = node.name })
end

--- Build menu items based on node type
--- @param node table Tree node
--- @return table menu_items
function M._build_menu_items(node)
  local items = {}
  
  if node.type == "solution" then
    table.insert(items, MenuItem:new("Add New Project", "create_project"))
    table.insert(items, MenuItem:new("Add Existing Project", "add_existing_project"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Build Solution", "build_solution"))
    table.insert(items, MenuItem:new("Rebuild Solution", "rebuild_solution"))
    table.insert(items, MenuItem:new("Clean Solution", "clean_solution"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Properties", "solution_properties"))
    
  elseif node.type == "project" then
    table.insert(items, MenuItem:new("Add New Item", "create_file"))
    table.insert(items, MenuItem:new("Add New Folder", "create_folder"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Add Reference", "add_reference"))
    table.insert(items, MenuItem:new("Manage NuGet Packages", "manage_packages"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Build", "build_project"))
    table.insert(items, MenuItem:new("Rebuild", "rebuild_project"))
    table.insert(items, MenuItem:new("Clean", "clean_project"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Run Tests", "run_tests"))
    table.insert(items, MenuItem:new("Debug", "debug_project"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Rename", "rename_item"))
    table.insert(items, MenuItem:new("Remove from Solution", "remove_project"))
    table.insert(items, MenuItem:new("Properties", "project_properties"))
    
  elseif node.type == "folder" then
    table.insert(items, MenuItem:new("Add New Item", "create_file"))
    table.insert(items, MenuItem:new("Add New Folder", "create_folder"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Rename", "rename_item"))
    table.insert(items, MenuItem:new("Delete", "delete_item"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Copy Path", "copy_path"))
    table.insert(items, MenuItem:new("Open in File Manager", "open_in_explorer"))
    
  elseif node.type == "file" then
    table.insert(items, MenuItem:new("Open", "open_item"))
    table.insert(items, MenuItem:new("Open With...", "open_with"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Rename", "rename_item"))
    table.insert(items, MenuItem:new("Delete", "delete_item"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Copy", "copy_item"))
    table.insert(items, MenuItem:new("Cut", "cut_item"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Copy Path", "copy_path"))
    table.insert(items, MenuItem:new("Properties", "file_properties"))
    
  elseif node.type == "reference" then
    if node.name == "References" then
      table.insert(items, MenuItem:new("Add Reference", "add_reference"))
      table.insert(items, MenuItem:new("Manage NuGet Packages", "manage_packages"))
    else
      table.insert(items, MenuItem:new("Remove Reference", "remove_reference"))
      table.insert(items, MenuItem:new("Properties", "reference_properties"))
    end
    
  elseif node.type == "package" then
    table.insert(items, MenuItem:new("Update Package", "update_package"))
    table.insert(items, MenuItem:new("Uninstall Package", "uninstall_package"))
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
    table.insert(items, MenuItem:new("Package Properties", "package_properties"))
  end
  
  -- Add common items
  if #items > 0 then
    table.insert(items, MenuItem:new("", nil, true, true)) -- Separator
  end
  table.insert(items, MenuItem:new("Refresh", "refresh_current"))
  
  return items
end

--- Create menu window
--- @param menu_items table Menu items
--- @param callbacks table Action callbacks
--- @param position table|nil Menu position
function M._create_menu_window(menu_items, callbacks, position)
  -- Calculate menu dimensions
  local max_width = 0
  local visible_items = 0
  
  for _, item in ipairs(menu_items) do
    if not item.separator then
      max_width = math.max(max_width, #item.label)
      visible_items = visible_items + 1
    else
      visible_items = visible_items + 1 -- Count separators too
    end
  end
  
  local width = math.max(max_width + 4, 20) -- Add padding
  local height = visible_items
  
  -- Calculate position
  local row, col
  if position then
    row = position.row or 1
    col = position.col or 1
  else
    -- Center on screen
    row = math.floor((vim.o.lines - height) / 2)
    col = math.floor((vim.o.columns - width) / 2)
  end
  
  -- Ensure menu fits on screen
  row = math.max(0, math.min(row, vim.o.lines - height - 2))
  col = math.max(0, math.min(col, vim.o.columns - width - 2))
  
  -- Create buffer
  menu_state.menu_buffer = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(menu_state.menu_buffer, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(menu_state.menu_buffer, 'swapfile', false)
  vim.api.nvim_buf_set_option(menu_state.menu_buffer, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(menu_state.menu_buffer, 'filetype', 'dotnet-context-menu')
  
  -- Create window
  menu_state.menu_window = vim.api.nvim_open_win(menu_state.menu_buffer, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    zindex = 1000
  })
  
  -- Set window options
  vim.api.nvim_win_set_option(menu_state.menu_window, 'number', false)
  vim.api.nvim_win_set_option(menu_state.menu_window, 'relativenumber', false)
  vim.api.nvim_win_set_option(menu_state.menu_window, 'cursorline', true)
  
  -- Populate menu
  M._populate_menu(menu_items, callbacks)
  
  -- Setup menu keymaps
  M._setup_menu_keymaps(menu_items, callbacks)
end

--- Populate menu with items
--- @param menu_items table Menu items
--- @param callbacks table Action callbacks
function M._populate_menu(menu_items, callbacks)
  local lines = {}
  local line_to_item = {}
  
  for i, item in ipairs(menu_items) do
    if item.separator then
      table.insert(lines, string.rep("─", vim.api.nvim_win_get_width(menu_state.menu_window) - 2))
    else
      local prefix = item.enabled and "  " or "  "
      local line = prefix .. item.label
      table.insert(lines, line)
      line_to_item[#lines] = i
    end
  end
  
  -- Set buffer content
  vim.api.nvim_buf_set_option(menu_state.menu_buffer, 'modifiable', true)
  vim.api.nvim_buf_set_lines(menu_state.menu_buffer, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(menu_state.menu_buffer, 'modifiable', false)
  
  -- Store mapping for later use
  menu_state.line_to_item = line_to_item
  menu_state.menu_items = menu_items
  menu_state.callbacks = callbacks
end

--- Setup menu keymaps
--- @param menu_items table Menu items
--- @param callbacks table Action callbacks
function M._setup_menu_keymaps(menu_items, callbacks)
  local opts = { buffer = menu_state.menu_buffer, silent = true }
  
  -- Enter to select
  vim.keymap.set('n', '<CR>', function()
    M._select_menu_item()
  end, opts)
  
  -- Escape to close
  vim.keymap.set('n', '<Esc>', function()
    M.close_menu()
  end, opts)
  
  -- Mouse click to select
  vim.keymap.set('n', '<LeftMouse>', function()
    M._select_menu_item()
  end, opts)
  
  -- Auto-close when focus is lost
  vim.api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
    buffer = menu_state.menu_buffer,
    once = true,
    callback = function()
      vim.schedule(function()
        M.close_menu()
      end)
    end
  })
end

--- Select current menu item
function M._select_menu_item()
  if not menu_state.menu_window or not vim.api.nvim_win_is_valid(menu_state.menu_window) then
    return
  end
  
  local cursor_line = vim.api.nvim_win_get_cursor(menu_state.menu_window)[1]
  local item_index = menu_state.line_to_item[cursor_line]
  
  if not item_index then
    return
  end
  
  local item = menu_state.menu_items[item_index]
  if not item or not item.enabled or item.separator then
    return
  end
  
  local callback = menu_state.callbacks[item.action]
  if callback then
    -- Close menu first
    M.close_menu()
    
    -- Execute callback
    local success, error_msg = pcall(callback, menu_state.current_node)
    if not success then
      logger.error("Context menu action failed", { 
        action = item.action, 
        error = error_msg 
      })
      vim.notify("Action failed: " .. item.label, vim.log.levels.ERROR)
    end
  else
    logger.warn("No callback found for action: " .. item.action)
    M.close_menu()
  end
end

--- Close context menu
function M.close_menu()
  if menu_state.menu_window and vim.api.nvim_win_is_valid(menu_state.menu_window) then
    vim.api.nvim_win_close(menu_state.menu_window, true)
  end
  
  if menu_state.menu_buffer and vim.api.nvim_buf_is_valid(menu_state.menu_buffer) then
    vim.api.nvim_buf_delete(menu_state.menu_buffer, { force = true })
  end
  
  menu_state.active = false
  menu_state.current_node = nil
  menu_state.menu_window = nil
  menu_state.menu_buffer = nil
  menu_state.line_to_item = nil
  menu_state.menu_items = nil
  menu_state.callbacks = nil
  
  logger.debug("Context menu closed")
end

--- Check if context menu is active
--- @return boolean active
function M.is_active()
  return menu_state.active
end

--- Get current menu node
--- @return table|nil node
function M.get_current_node()
  return menu_state.current_node
end

--- Add custom menu item for node type
--- @param node_type string Node type
--- @param item table Menu item
function M.add_custom_item(node_type, item)
  -- This could be implemented to allow custom menu items
  -- For now, it's a placeholder for extensibility
  logger.debug("Custom menu item added", { node_type = node_type, item = item.label })
end

--- Cleanup context menu manager
function M.cleanup()
  M.close_menu()
  logger.debug("Context menu manager cleaned up")
end

return M
