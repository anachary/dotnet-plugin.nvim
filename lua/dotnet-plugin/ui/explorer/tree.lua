-- Tree Management Module for Enhanced Solution Explorer
-- Single Responsibility: Manages tree data structure, rendering, and navigation

local M = {}

local logger = require('dotnet-plugin.core.logger')

-- Tree state
local tree_state = {
  data = {},
  expanded_nodes = {},
  selected_node = nil,
  filter_text = "",
  show_hidden_files = false,
  line_to_node_map = {}
}

-- Node types
M.NODE_TYPES = {
  SOLUTION = "solution",
  PROJECT = "project",
  FOLDER = "folder", 
  FILE = "file",
  REFERENCE = "reference",
  PACKAGE = "package",
  DEPENDENCY = "dependency"
}

--- Initialize tree manager
--- @param opts table|nil Configuration options
--- @return boolean success
function M.setup(opts)
  tree_state = vim.tbl_deep_extend("force", tree_state, opts or {})
  logger.debug("Tree manager initialized")
  return true
end

--- Load solution data into tree
--- @param solution_file string Solution file path
--- @return boolean success
function M.load_solution(solution_file)
  -- Simple implementation - would parse solution file in real implementation
  tree_state.data = {
    type = M.NODE_TYPES.SOLUTION,
    name = vim.fn.fnamemodify(solution_file, ":t"),
    path = solution_file,
    expanded = true,
    children = {},
    id = "solution:" .. solution_file
  }
  
  tree_state.expanded_nodes = {}
  tree_state.line_to_node_map = {}
  
  logger.info("Solution loaded into tree", { path = solution_file })
  return true
end

--- Render tree to buffer
--- @param buffer number Buffer ID
function M.render(buffer)
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  
  local lines = {}
  tree_state.line_to_node_map = {}
  
  if vim.tbl_isempty(tree_state.data) then
    table.insert(lines, "No solution loaded")
  else
    M._render_node(tree_state.data, lines, 0)
  end
  
  -- Apply filter if active
  if tree_state.filter_text ~= "" then
    lines = M._apply_filter(lines)
  end
  
  -- Update buffer content
  vim.api.nvim_buf_set_option(buffer, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buffer, 'modifiable', false)
  
  logger.debug("Tree rendered", { lines = #lines })
end

--- Render a single tree node
--- @param node table Node to render
--- @param lines table Lines array
--- @param depth number Indentation depth
function M._render_node(node, lines, depth)
  local line_number = #lines + 1
  tree_state.line_to_node_map[line_number] = node
  
  local indent = string.rep("  ", depth)
  local icon = M._get_node_icon(node.type)
  local expand_icon = ""
  
  if node.children and #node.children > 0 then
    expand_icon = M._is_expanded(node) and "▼ " or "▶ "
  else
    expand_icon = "  "
  end
  
  local line = indent .. expand_icon .. icon .. node.name
  table.insert(lines, line)
  
  -- Render children if expanded
  if M._is_expanded(node) and node.children then
    for _, child in ipairs(node.children) do
      M._render_node(child, lines, depth + 1)
    end
  end
end

--- Get icon for node type
--- @param node_type string Node type
--- @return string icon
function M._get_node_icon(node_type)
  local icons = {
    [M.NODE_TYPES.SOLUTION] = "󰘐 ",
    [M.NODE_TYPES.PROJECT] = "󰏗 ",
    [M.NODE_TYPES.FOLDER] = "󰉋 ",
    [M.NODE_TYPES.FILE] = "󰈙 ",
    [M.NODE_TYPES.REFERENCE] = "󰌹 ",
    [M.NODE_TYPES.PACKAGE] = "󰏖 ",
    [M.NODE_TYPES.DEPENDENCY] = "󰑴 "
  }
  return icons[node_type] or "  "
end

--- Check if node is expanded
--- @param node table Node to check
--- @return boolean is_expanded
function M._is_expanded(node)
  return node.expanded or tree_state.expanded_nodes[node.id] == true
end

--- Toggle node expansion
--- @param node table Node to toggle
function M.toggle_node(node)
  if node and (node.children and #node.children > 0) then
    if node.expanded ~= nil then
      node.expanded = not node.expanded
    else
      tree_state.expanded_nodes[node.id] = not (tree_state.expanded_nodes[node.id] or false)
    end
    
    logger.debug("Node toggled", { 
      node = node.name, 
      expanded = M._is_expanded(node) 
    })
  end
end

--- Get node at specific line
--- @param line_number number Line number (1-based)
--- @return table|nil node
function M.get_node_at_line(line_number)
  return tree_state.line_to_node_map[line_number]
end

--- Set filter text
--- @param filter string Filter text
function M.set_filter(filter)
  tree_state.filter_text = filter or ""
  logger.debug("Filter set", { filter = tree_state.filter_text })
end

--- Apply filter to lines
--- @param lines table Original lines
--- @return table filtered_lines
function M._apply_filter(lines)
  if tree_state.filter_text == "" then
    return lines
  end
  
  local filtered = {}
  local filter_lower = tree_state.filter_text:lower()
  
  for _, line in ipairs(lines) do
    if line:lower():find(filter_lower, 1, true) then
      table.insert(filtered, line)
    end
  end
  
  return filtered
end

--- Toggle hidden files visibility
function M.toggle_hidden_files()
  tree_state.show_hidden_files = not tree_state.show_hidden_files
  logger.debug("Hidden files toggled", { show = tree_state.show_hidden_files })
end

--- Get current tree data
--- @return table tree_data
function M.get_tree_data()
  return tree_state.data
end

--- Clear tree data
function M.clear()
  tree_state.data = {}
  tree_state.expanded_nodes = {}
  tree_state.selected_node = nil
  tree_state.line_to_node_map = {}
  logger.debug("Tree cleared")
end

--- Get tree state
--- @return table state
function M.get_state()
  return vim.deepcopy(tree_state)
end

return M
