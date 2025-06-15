-- Solution Explorer for dotnet-plugin.nvim
-- Provides tree view for solution and project hierarchy

local M = {}

local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

-- Solution explorer state
local explorer_initialized = false
local explorer_buffer = nil
local explorer_window = nil
local current_solution = nil
local tree_data = {}

-- Tree node types
local NODE_TYPES = {
  SOLUTION = "solution",
  PROJECT = "project",
  FOLDER = "folder",
  FILE = "file"
}

-- Tree icons
local ICONS = {
  [NODE_TYPES.SOLUTION] = "󰘐 ",
  [NODE_TYPES.PROJECT] = "󰏗 ",
  [NODE_TYPES.FOLDER] = "󰉋 ",
  [NODE_TYPES.FILE] = "󰈙 ",
  expanded = "󰅀 ",
  collapsed = "󰅂 "
}

--- Setup the solution explorer
--- @return boolean success True if explorer was initialized successfully
function M.setup()
  if explorer_initialized then
    return true
  end

  local explorer_config = config.get_value("ui.solution_explorer") or {}
  
  logger.debug("Initializing solution explorer")

  -- Setup keymaps and autocommands
  M._setup_keymaps()
  M._setup_autocommands()
  
  explorer_initialized = true
  logger.debug("Solution explorer initialized")
  
  return true
end

--- Setup keymaps for solution explorer
function M._setup_keymaps()
  -- Global keymaps
  local keymap_config = config.get_value("ui.solution_explorer.keymaps") or {}
  
  if keymap_config.toggle then
    vim.keymap.set('n', keymap_config.toggle, function()
      M.toggle()
    end, { desc = 'Toggle .NET Solution Explorer' })
  end
end

--- Setup autocommands for solution explorer
function M._setup_autocommands()
  local augroup = vim.api.nvim_create_augroup("DotnetSolutionExplorer", { clear = true })
  
  -- Auto-close when last window
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      if explorer_window and tonumber(args.match) == explorer_window then
        explorer_window = nil
      end
    end
  })
end

--- Load solution data into explorer
--- @param solution_data table Solution information
function M.load_solution(solution_data)
  current_solution = solution_data
  tree_data = M._build_tree_data(solution_data)
  
  if M.is_open() then
    M._render_tree()
  end
  
  logger.debug("Solution loaded in explorer", { path = solution_data.path })
end

--- Clear solution from explorer
function M.clear_solution()
  current_solution = nil
  tree_data = {}
  
  if M.is_open() then
    M._render_tree()
  end
  
  logger.debug("Solution cleared from explorer")
end

--- Refresh project in explorer
--- @param project_data table Project information
function M.refresh_project(project_data)
  if current_solution then
    -- Rebuild tree data with updated project
    tree_data = M._build_tree_data(current_solution)
    
    if M.is_open() then
      M._render_tree()
    end
  end
end

--- Build tree data structure from solution
--- @param solution_data table Solution information
--- @return table Tree data structure
function M._build_tree_data(solution_data)
  local tree = {
    type = NODE_TYPES.SOLUTION,
    name = vim.fn.fnamemodify(solution_data.path, ":t"),
    path = solution_data.path,
    expanded = true,
    children = {}
  }
  
  -- Add projects
  if solution_data.projects then
    for _, project in ipairs(solution_data.projects) do
      local project_node = {
        type = NODE_TYPES.PROJECT,
        name = vim.fn.fnamemodify(project.path, ":t:r"),
        path = project.path,
        expanded = false,
        children = {}
      }
      
      -- Add project files (simplified for now)
      if project.source_files then
        for _, file in ipairs(project.source_files) do
          table.insert(project_node.children, {
            type = NODE_TYPES.FILE,
            name = vim.fn.fnamemodify(file, ":t"),
            path = file,
            children = {}
          })
        end
      end
      
      table.insert(tree.children, project_node)
    end
  end
  
  return tree
end

--- Check if explorer is open
--- @return boolean True if explorer window is open
function M.is_open()
  return explorer_window and vim.api.nvim_win_is_valid(explorer_window)
end

--- Toggle solution explorer
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

--- Open solution explorer
function M.open()
  if M.is_open() then
    return
  end
  
  local explorer_config = config.get_value("ui.solution_explorer") or {}
  local width = explorer_config.width or 30
  local position = explorer_config.position or "left"
  
  -- Create buffer if it doesn't exist
  if not explorer_buffer or not vim.api.nvim_buf_is_valid(explorer_buffer) then
    explorer_buffer = vim.api.nvim_create_buf(false, true)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(explorer_buffer, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(explorer_buffer, 'swapfile', false)
    vim.api.nvim_buf_set_option(explorer_buffer, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(explorer_buffer, 'filetype', 'dotnet-solution-explorer')
    vim.api.nvim_buf_set_name(explorer_buffer, '.NET Solution Explorer')
    
    -- Set buffer keymaps
    M._setup_buffer_keymaps(explorer_buffer)
  end
  
  -- Create window
  local win_config = {
    split = position == "right" and "right" or "left",
    win = 0
  }
  
  explorer_window = vim.api.nvim_open_win(explorer_buffer, false, win_config)
  
  -- Set window options
  vim.api.nvim_win_set_width(explorer_window, width)
  vim.api.nvim_win_set_option(explorer_window, 'number', false)
  vim.api.nvim_win_set_option(explorer_window, 'relativenumber', false)
  vim.api.nvim_win_set_option(explorer_window, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(explorer_window, 'foldcolumn', '0')
  vim.api.nvim_win_set_option(explorer_window, 'wrap', false)
  
  -- Render tree
  M._render_tree()
  
  logger.debug("Solution explorer opened")
end

--- Close solution explorer
function M.close()
  if explorer_window and vim.api.nvim_win_is_valid(explorer_window) then
    vim.api.nvim_win_close(explorer_window, false)
    explorer_window = nil
    logger.debug("Solution explorer closed")
  end
end

--- Setup buffer-specific keymaps
--- @param buffer number Buffer handle
function M._setup_buffer_keymaps(buffer)
  local opts = { buffer = buffer, silent = true }
  
  -- Navigation
  vim.keymap.set('n', '<CR>', M._on_enter, opts)
  vim.keymap.set('n', 'o', M._on_enter, opts)
  vim.keymap.set('n', '<2-LeftMouse>', M._on_enter, opts)
  
  -- Tree operations
  vim.keymap.set('n', '<Tab>', M._toggle_node, opts)
  vim.keymap.set('n', '<Space>', M._toggle_node, opts)
  
  -- File operations
  vim.keymap.set('n', 'r', M._refresh, opts)
  vim.keymap.set('n', 'R', M._refresh_all, opts)
  
  -- Window operations
  vim.keymap.set('n', 'q', M.close, opts)
  vim.keymap.set('n', '<Esc>', M.close, opts)
end

--- Handle enter key press
function M._on_enter()
  local line = vim.api.nvim_win_get_cursor(explorer_window)[1]
  local node = M._get_node_at_line(line)
  
  if not node then
    return
  end
  
  if node.type == NODE_TYPES.FILE then
    -- Open file
    vim.cmd('edit ' .. vim.fn.fnameescape(node.path))
  elseif node.type == NODE_TYPES.PROJECT or node.type == NODE_TYPES.FOLDER then
    -- Toggle expansion
    M._toggle_node()
  end
end

--- Toggle node expansion
function M._toggle_node()
  local line = vim.api.nvim_win_get_cursor(explorer_window)[1]
  local node = M._get_node_at_line(line)
  
  if node and (node.type == NODE_TYPES.PROJECT or node.type == NODE_TYPES.FOLDER or node.type == NODE_TYPES.SOLUTION) then
    node.expanded = not node.expanded
    M._render_tree()
  end
end

--- Refresh current node
function M._refresh()
  -- TODO: Implement refresh logic
  logger.debug("Refreshing solution explorer node")
end

--- Refresh entire tree
function M._refresh_all()
  if current_solution then
    events.emit(events.EVENTS.SOLUTION_RELOAD_REQUESTED, { path = current_solution.path })
  end
end

--- Get node at specific line
--- @param line number Line number (1-based)
--- @return table|nil Node data
function M._get_node_at_line(line)
  -- TODO: Implement line-to-node mapping
  return nil
end

--- Render tree in buffer
function M._render_tree()
  if not explorer_buffer or not vim.api.nvim_buf_is_valid(explorer_buffer) then
    return
  end
  
  local lines = {}
  
  if vim.tbl_isempty(tree_data) then
    table.insert(lines, "No solution loaded")
  else
    M._render_node(tree_data, lines, 0)
  end
  
  -- Set buffer content
  vim.api.nvim_buf_set_option(explorer_buffer, 'modifiable', true)
  vim.api.nvim_buf_set_lines(explorer_buffer, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(explorer_buffer, 'modifiable', false)
end

--- Render a tree node
--- @param node table Node data
--- @param lines table Lines array to append to
--- @param depth number Indentation depth
function M._render_node(node, lines, depth)
  local indent = string.rep("  ", depth)
  local icon = ICONS[node.type] or ""
  local expand_icon = ""
  
  if node.children and #node.children > 0 then
    expand_icon = node.expanded and ICONS.expanded or ICONS.collapsed
  end
  
  local line = indent .. expand_icon .. icon .. node.name
  table.insert(lines, line)
  
  -- Render children if expanded
  if node.expanded and node.children then
    for _, child in ipairs(node.children) do
      M._render_node(child, lines, depth + 1)
    end
  end
end

--- Shutdown solution explorer
function M.shutdown()
  if explorer_initialized then
    M.close()
    
    if explorer_buffer and vim.api.nvim_buf_is_valid(explorer_buffer) then
      vim.api.nvim_buf_delete(explorer_buffer, { force = true })
      explorer_buffer = nil
    end
    
    explorer_initialized = false
    logger.debug("Solution explorer shutdown")
  end
end

return M
