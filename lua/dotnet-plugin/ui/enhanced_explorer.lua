-- Enhanced Solution Explorer for dotnet-plugin.nvim
-- Modular design following SOLID principles

local M = {}

-- Import core dependencies
local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')

-- Import specialized modules (following Single Responsibility Principle)
local ExplorerWindow = require('dotnet-plugin.ui.explorer.window')
local ExplorerTree = require('dotnet-plugin.ui.explorer.tree')
local FileOperations = require('dotnet-plugin.ui.explorer.file_operations')
local ProjectTemplates = require('dotnet-plugin.ui.explorer.project_templates')
local KeymapManager = require('dotnet-plugin.ui.explorer.keymap_manager')
local ContextMenu = require('dotnet-plugin.ui.explorer.context_menu')

-- Enhanced explorer state (minimal, following SRP)
M._initialized = false
M._components = {}

-- Interface for component communication (Dependency Inversion Principle)
local IExplorerComponent = {
  setup = function(self, opts) end,
  cleanup = function(self) end
}

--- Setup enhanced solution explorer (following Dependency Injection)
--- @param opts table|nil Configuration options
--- @return boolean success True if setup succeeded
function M.setup(opts)
  if M._initialized then
    return true
  end

  opts = opts or {}

  -- Initialize components (Dependency Injection)
  M._components.window = ExplorerWindow
  M._components.tree = ExplorerTree
  M._components.file_ops = FileOperations
  M._components.templates = ProjectTemplates
  M._components.keymaps = KeymapManager
  M._components.context_menu = ContextMenu

  -- Setup all components
  local success = M._setup_components(opts)
  if not success then
    logger.error("Failed to setup enhanced explorer components")
    return false
  end

  -- Setup event handlers
  M._setup_event_handlers()

  -- Register enhanced commands
  M._register_enhanced_commands()

  M._initialized = true
  logger.info("Enhanced solution explorer initialized with modular architecture")

  return true
end

--- Setup components (Single Responsibility Principle)
--- @param opts table Configuration options
--- @return boolean success
function M._setup_components(opts)
  local component_configs = {
    window = opts.window or {},
    tree = opts.tree or {},
    file_ops = opts.file_operations or {},
    templates = opts.templates or {},
    keymaps = opts.keymaps or {},
    context_menu = opts.context_menu or {}
  }

  -- Setup each component
  for name, component in pairs(M._components) do
    local config = component_configs[name] or {}
    local success = component.setup(config)
    if not success then
      logger.error("Failed to setup component: " .. name)
      return false
    end
  end

  return true
end

--- Register enhanced commands (Interface Segregation Principle)
function M._register_enhanced_commands()
  local commands = {
    {
      name = 'DotnetExplorerEnhanced',
      func = function() M.open() end,
      opts = { desc = 'Open enhanced solution explorer' }
    },
    {
      name = 'DotnetCreateFile',
      func = function(opts) M.create_file_interactive(opts.args) end,
      opts = { nargs = '?', desc = 'Create new file with template' }
    },
    {
      name = 'DotnetCreateProject',
      func = function(opts) M.create_project_interactive(opts.args) end,
      opts = { nargs = '?', desc = 'Create new project from template' }
    },
    {
      name = 'DotnetExplorerFilter',
      func = function(opts) M.set_filter(opts.args) end,
      opts = { nargs = '?', desc = 'Filter explorer contents' }
    }
  }

  -- Register all commands
  for _, cmd in ipairs(commands) do
    vim.api.nvim_create_user_command(cmd.name, cmd.func, cmd.opts)
  end

  logger.debug("Enhanced explorer commands registered")
end

--- Setup event handlers (Observer Pattern)
function M._setup_event_handlers()
  local event_handlers = {
    [events.EVENTS.SOLUTION_LOADED] = function(data)
      M.load_solution(data.solution_file)
    end,

    [events.EVENTS.PROJECT_CHANGED] = function(data)
      M.refresh_project(data.project_file)
    end,

    ["file_created"] = function(data)
      M.refresh_tree()
    end,

    ["file_deleted"] = function(data)
      M.refresh_tree()
    end,

    ["file_renamed"] = function(data)
      M.refresh_tree()
    end,

    ["project_created"] = function(data)
      M.refresh_tree()
    end
  }

  -- Subscribe to all events
  for event, handler in pairs(event_handlers) do
    events.subscribe(event, handler)
  end

  logger.debug("Enhanced explorer event handlers setup")
end

--- Open enhanced solution explorer (Facade Pattern)
function M.open()
  if M.is_open() then
    M._components.window.focus()
    return
  end

  -- Create window and buffer
  local window_id = M._components.window.create_window()
  local buffer_id = M._components.window.get_buffer()

  if not window_id or not buffer_id then
    logger.error("Failed to create explorer window")
    return
  end

  -- Setup keymaps with callbacks
  local callbacks = M._create_action_callbacks()
  M._components.keymaps.setup(buffer_id, callbacks)

  -- Load current solution if available
  local solution_file = M._find_solution_file()
  if solution_file then
    M.load_solution(solution_file)
  else
    M._show_no_solution_message()
  end

  logger.info("Enhanced solution explorer opened")
end

--- Load solution into explorer
--- @param solution_file string Solution file path
function M.load_solution(solution_file)
  local success = M._components.tree.load_solution(solution_file)
  if success then
    M.refresh_tree()
  end
end

--- Refresh tree display
function M.refresh_tree()
  local buffer = M._components.window.get_buffer()
  if buffer then
    M._components.tree.render(buffer)
  end
end

--- Check if explorer is open
--- @return boolean is_open
function M.is_open()
  return M._components.window.is_open()
end

--- Close explorer
function M.close()
  M._components.window.close()
end

--- Set filter text
--- @param filter string Filter text
function M.set_filter(filter)
  M._components.tree.set_filter(filter)
  M.refresh_tree()
end

--- Create action callbacks (Command Pattern)
--- @return table callbacks
function M._create_action_callbacks()
  return {
    open_item = function()
      local node = M._get_current_node()
      if node then
        M._handle_open_item(node)
      end
    end,

    toggle_node = function()
      local node = M._get_current_node()
      if node then
        M._components.tree.toggle_node(node)
        M.refresh_tree()
      end
    end,

    create_file = function()
      M.create_file_interactive()
    end,

    create_folder = function()
      M.create_folder_interactive()
    end,

    create_project = function()
      M.create_project_interactive()
    end,

    rename_item = function()
      local node = M._get_current_node()
      if node then
        M._handle_rename(node)
      end
    end,

    delete_item = function()
      local node = M._get_current_node()
      if node then
        M._handle_delete(node)
      end
    end,

    show_context_menu = function()
      local node = M._get_current_node()
      if node then
        local callbacks = M._create_context_menu_callbacks()
        M._components.context_menu.show_menu(node, callbacks)
      end
    end,

    close_explorer = function()
      M.close()
    end,

    show_help = function()
      M._show_help()
    end,

    refresh_all = function()
      local solution_file = M._find_solution_file()
      if solution_file then
        M.load_solution(solution_file)
      end
    end,

    refresh_current = function()
      M.refresh_tree()
    end,

    filter_items = function()
      local filter = vim.fn.input("Filter: ")
      M.set_filter(filter)
    end,

    toggle_hidden_files = function()
      M._components.tree.toggle_hidden_files()
      M.refresh_tree()
    end
  }
end

--- Get current node under cursor
--- @return table|nil node
function M._get_current_node()
  local window = M._components.window.get_window()
  if not window or not vim.api.nvim_win_is_valid(window) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(window)[1]
  return M._components.tree.get_node_at_line(line)
end

--- Handle opening an item
--- @param node table Tree node
function M._handle_open_item(node)
  if node.type == "file" then
    vim.cmd('edit ' .. vim.fn.fnameescape(node.path))
  elseif node.type == "project" or node.type == "folder" then
    M._components.tree.toggle_node(node)
    M.refresh_tree()
  end
end

--- Handle renaming an item
--- @param node table Tree node
function M._handle_rename(node)
  local new_name = vim.fn.input("New name: ", vim.fn.fnamemodify(node.path, ":t"))
  if new_name ~= "" then
    M._components.file_ops.rename(node.path, new_name)
  end
end

--- Handle deleting an item
--- @param node table Tree node
function M._handle_delete(node)
  M._components.file_ops.delete(node.path)
end

--- Create file interactively
function M.create_file_interactive()
  local current_node = M._get_current_node()
  if not current_node then
    return
  end

  local templates = M._components.file_ops.get_file_templates()
  local template_names = {}
  for _, template in ipairs(templates) do
    table.insert(template_names, template.name)
  end

  vim.ui.select(template_names, {
    prompt = 'Select file template:',
  }, function(choice)
    if choice then
      local template = nil
      for _, t in ipairs(templates) do
        if t.name == choice then
          template = t
          break
        end
      end

      if template then
        local file_name = vim.fn.input("File name: ")
        if file_name ~= "" then
          local parent_path = M._get_parent_path(current_node)
          M._components.file_ops.create_file(parent_path, template, file_name)
        end
      end
    end
  end)
end

--- Create folder interactively
function M.create_folder_interactive()
  local current_node = M._get_current_node()
  if not current_node then
    return
  end

  local folder_name = vim.fn.input("Folder name: ")
  if folder_name ~= "" then
    local parent_path = M._get_parent_path(current_node)
    M._components.file_ops.create_folder(parent_path, folder_name)
  end
end

--- Create project interactively
function M.create_project_interactive()
  local templates = M._components.templates.get_templates()
  local template_names = {}
  for _, template in ipairs(templates) do
    table.insert(template_names, template.name)
  end

  vim.ui.select(template_names, {
    prompt = 'Select project template:',
  }, function(choice)
    if choice then
      local template = M._components.templates.get_template_by_name(choice)
      if template then
        local project_name = vim.fn.input("Project name: ")
        if project_name ~= "" then
          local output_dir = M._get_solution_directory() or vim.fn.getcwd()
          M._components.templates.create_project(template, project_name, output_dir)
        end
      end
    end
  end)
end

--- Get parent path for a node
--- @param node table Tree node
--- @return string parent_path
function M._get_parent_path(node)
  if node.type == "folder" then
    return node.path
  elseif node.type == "file" then
    return vim.fn.fnamemodify(node.path, ":h")
  elseif node.type == "project" then
    return vim.fn.fnamemodify(node.path, ":h")
  else
    return vim.fn.getcwd()
  end
end

--- Get solution directory
--- @return string|nil solution_dir
function M._get_solution_directory()
  local solution_file = M._find_solution_file()
  if solution_file then
    return vim.fn.fnamemodify(solution_file, ':h')
  end
  return nil
end

--- Find solution file
--- @return string|nil solution_file
function M._find_solution_file()
  local current_dir = vim.fn.getcwd()

  while current_dir ~= '/' and current_dir ~= '' do
    local solution_files = vim.fn.glob(current_dir .. '/*.sln', false, true)
    if #solution_files > 0 then
      return solution_files[1]
    end
    current_dir = vim.fn.fnamemodify(current_dir, ':h')
  end

  return nil
end

--- Create context menu callbacks
--- @return table callbacks
function M._create_context_menu_callbacks()
  return {
    create_file = function() M.create_file_interactive() end,
    create_folder = function() M.create_folder_interactive() end,
    create_project = function() M.create_project_interactive() end,
    rename_item = function(node) M._handle_rename(node) end,
    delete_item = function(node) M._handle_delete(node) end,
    open_item = function(node) M._handle_open_item(node) end,
    refresh_current = function() M.refresh_tree() end
  }
end

--- Show help dialog
function M._show_help()
  local help_lines = M._components.keymaps.get_help_text()

  -- Create help buffer
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
  vim.api.nvim_buf_set_option(help_buf, 'modifiable', false)

  -- Create help window
  local help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = 'editor',
    width = 60,
    height = math.min(#help_lines + 2, vim.o.lines - 4),
    col = math.floor((vim.o.columns - 60) / 2),
    row = math.floor((vim.o.lines - #help_lines) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Help ',
    title_pos = 'center'
  })

  -- Close help on any key
  vim.keymap.set('n', '<buffer>', function()
    vim.api.nvim_win_close(help_win, true)
  end, { buffer = help_buf })
end

--- Show no solution message
function M._show_no_solution_message()
  local buffer = M._components.window.get_buffer()
  if buffer then
    local lines = {
      "No .NET solution found",
      "",
      "To get started:",
      "• Open a directory containing a .sln file",
      "• Create a new solution with :DotnetCreateProject",
      "• Use 'p' to create a new project"
    }

    vim.api.nvim_buf_set_option(buffer, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buffer, 'modifiable', false)
  end
end

--- Refresh project node
--- @param project_file string Project file path
function M.refresh_project(project_file)
  -- Reload the tree to pick up project changes
  local solution_file = M._find_solution_file()
  if solution_file then
    M.load_solution(solution_file)
  end
end

--- Shutdown enhanced explorer (following SOLID principles)
function M.shutdown()
  if M._initialized then
    -- Cleanup all components
    for name, component in pairs(M._components) do
      if component.cleanup then
        component.cleanup()
      end
    end

    M._components = {}
    M._initialized = false

    logger.info("Enhanced solution explorer shutdown")
  end
end

return M
