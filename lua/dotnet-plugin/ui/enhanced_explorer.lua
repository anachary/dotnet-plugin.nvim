-- Enhanced Solution Explorer for dotnet-plugin.nvim
-- Provides advanced file operations, project templates, and enhanced navigation

local M = {}

-- Import dependencies
local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')
local process = require('dotnet-plugin.core.process')
local solution_parser = require('dotnet-plugin.solution.parser')
local project_parser = require('dotnet-plugin.project.parser')

-- Enhanced explorer state
M._initialized = false
M._explorer_buf = nil
M._explorer_win = nil
M._tree_data = {}
M._expanded_nodes = {}
M._selected_node = nil
M._filter_text = ""
M._show_hidden_files = false
M._context_menu_active = false

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

-- File operation types
M.FILE_OPERATIONS = {
  CREATE_FILE = "create_file",
  CREATE_FOLDER = "create_folder",
  CREATE_PROJECT = "create_project",
  RENAME = "rename",
  DELETE = "delete",
  COPY = "copy",
  MOVE = "move",
  ADD_REFERENCE = "add_reference",
  MANAGE_PACKAGES = "manage_packages"
}

-- Project templates
M.PROJECT_TEMPLATES = {
  {name = "Console Application", template = "console", framework = "net8.0"},
  {name = "Class Library", template = "classlib", framework = "net8.0"},
  {name = "Web API", template = "webapi", framework = "net8.0"},
  {name = "MVC Web App", template = "mvc", framework = "net8.0"},
  {name = "Blazor Server", template = "blazorserver", framework = "net8.0"},
  {name = "Worker Service", template = "worker", framework = "net8.0"},
  {name = "xUnit Test Project", template = "xunit", framework = "net8.0"},
  {name = "NUnit Test Project", template = "nunit", framework = "net8.0"}
}

-- File templates
M.FILE_TEMPLATES = {
  {name = "Class", extension = "cs", template = "class"},
  {name = "Interface", extension = "cs", template = "interface"},
  {name = "Enum", extension = "cs", template = "enum"},
  {name = "Record", extension = "cs", template = "record"},
  {name = "Controller", extension = "cs", template = "controller"},
  {name = "Service", extension = "cs", template = "service"},
  {name = "Model", extension = "cs", template = "model"},
  {name = "Configuration", extension = "json", template = "config"}
}

--- Setup enhanced solution explorer
--- @param opts table|nil Configuration options
--- @return boolean success True if setup succeeded
function M.setup(opts)
  if M._initialized then
    return true
  end

  opts = opts or {}
  
  -- Setup event handlers
  M._setup_event_handlers()
  
  -- Register enhanced commands
  M._register_enhanced_commands()

  M._initialized = true
  logger.info("Enhanced solution explorer initialized")
  
  return true
end

--- Register enhanced commands
function M._register_enhanced_commands()
  -- Enhanced explorer commands
  vim.api.nvim_create_user_command('DotnetExplorerEnhanced', function()
    M.open_enhanced()
  end, {
    desc = 'Open enhanced solution explorer'
  })
  
  -- File operations
  vim.api.nvim_create_user_command('DotnetCreateFile', function(opts)
    M.create_file(opts.args)
  end, {
    nargs = '?',
    desc = 'Create new file with template'
  })
  
  vim.api.nvim_create_user_command('DotnetCreateProject', function(opts)
    M.create_project(opts.args)
  end, {
    nargs = '?',
    desc = 'Create new project from template'
  })
  
  vim.api.nvim_create_user_command('DotnetRenameFile', function()
    M.rename_selected()
  end, {
    desc = 'Rename selected file/folder'
  })
  
  vim.api.nvim_create_user_command('DotnetDeleteFile', function()
    M.delete_selected()
  end, {
    desc = 'Delete selected file/folder'
  })
  
  -- Project operations
  vim.api.nvim_create_user_command('DotnetAddReference', function(opts)
    M.add_project_reference(opts.args)
  end, {
    nargs = '?',
    desc = 'Add project reference'
  })
  
  vim.api.nvim_create_user_command('DotnetManagePackages', function()
    M.manage_nuget_packages()
  end, {
    desc = 'Manage NuGet packages'
  })
  
  -- Search and filter
  vim.api.nvim_create_user_command('DotnetExplorerFilter', function(opts)
    M.set_filter(opts.args)
  end, {
    nargs = '?',
    desc = 'Filter explorer contents'
  })
  
  vim.api.nvim_create_user_command('DotnetExplorerSearch', function(opts)
    M.search_files(opts.args)
  end, {
    nargs = '?',
    desc = 'Search files in solution'
  })
  
  logger.debug("Enhanced explorer commands registered")
end

--- Setup event handlers
function M._setup_event_handlers()
  -- Listen for solution changes
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M._load_enhanced_solution(data.solution_file)
  end)
  
  -- Listen for project changes
  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M._refresh_project_node(data.project_file)
  end)
  
  -- Listen for file system changes
  events.subscribe("file_created", function(data)
    M._handle_file_created(data.file_path)
  end)
  
  events.subscribe("file_deleted", function(data)
    M._handle_file_deleted(data.file_path)
  end)
  
  events.subscribe("file_renamed", function(data)
    M._handle_file_renamed(data.old_path, data.new_path)
  end)
  
  logger.debug("Enhanced explorer event handlers setup")
end

--- Open enhanced solution explorer
function M.open_enhanced()
  if M._is_open() then
    return
  end
  
  -- Create enhanced explorer buffer
  M._create_enhanced_buffer()
  
  -- Create enhanced explorer window
  M._create_enhanced_window()
  
  -- Setup enhanced keymaps
  M._setup_enhanced_keymaps()
  
  -- Load current solution if available
  local solution_file = M._find_solution_file()
  if solution_file then
    M._load_enhanced_solution(solution_file)
  else
    M._show_no_solution_message()
  end
  
  logger.info("Enhanced solution explorer opened")
end

--- Create enhanced explorer buffer
function M._create_enhanced_buffer()
  M._explorer_buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(M._explorer_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(M._explorer_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(M._explorer_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(M._explorer_buf, 'filetype', 'dotnet-enhanced-explorer')
  vim.api.nvim_buf_set_name(M._explorer_buf, '.NET Enhanced Explorer')
end

--- Create enhanced explorer window
function M._create_enhanced_window()
  local explorer_config = config.get_value("ui.enhanced_explorer") or {}
  local width = explorer_config.width or 35
  local height = explorer_config.height or vim.o.lines - 10
  local position = explorer_config.position or "left"
  
  -- Create floating window for enhanced features
  local win_config = {
    relative = 'editor',
    width = width,
    height = height,
    col = position == "right" and (vim.o.columns - width - 2) or 1,
    row = 1,
    style = 'minimal',
    border = 'rounded',
    title = ' .NET Enhanced Explorer ',
    title_pos = 'center'
  }
  
  M._explorer_win = vim.api.nvim_open_win(M._explorer_buf, true, win_config)
  
  -- Set window options
  vim.api.nvim_win_set_option(M._explorer_win, 'number', false)
  vim.api.nvim_win_set_option(M._explorer_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(M._explorer_win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(M._explorer_win, 'wrap', false)
  vim.api.nvim_win_set_option(M._explorer_win, 'cursorline', true)
end

--- Setup enhanced keymaps
function M._setup_enhanced_keymaps()
  local opts = { buffer = M._explorer_buf, silent = true }
  
  -- Navigation
  vim.keymap.set('n', '<CR>', M._on_enter_enhanced, opts)
  vim.keymap.set('n', 'o', M._on_enter_enhanced, opts)
  vim.keymap.set('n', '<2-LeftMouse>', M._on_enter_enhanced, opts)
  
  -- Tree operations
  vim.keymap.set('n', '<Tab>', M._toggle_node_enhanced, opts)
  vim.keymap.set('n', '<Space>', M._toggle_node_enhanced, opts)
  vim.keymap.set('n', 'za', M._toggle_node_enhanced, opts)
  
  -- File operations
  vim.keymap.set('n', 'a', M._create_file_interactive, opts)
  vim.keymap.set('n', 'A', M._create_folder_interactive, opts)
  vim.keymap.set('n', 'p', M._create_project_interactive, opts)
  vim.keymap.set('n', 'r', M._rename_interactive, opts)
  vim.keymap.set('n', 'd', M._delete_interactive, opts)
  vim.keymap.set('n', 'c', M._copy_interactive, opts)
  vim.keymap.set('n', 'm', M._move_interactive, opts)
  
  -- Project operations
  vim.keymap.set('n', 'R', M._add_reference_interactive, opts)
  vim.keymap.set('n', 'P', M._manage_packages_interactive, opts)
  
  -- Search and filter
  vim.keymap.set('n', '/', M._filter_interactive, opts)
  vim.keymap.set('n', 'f', M._search_interactive, opts)
  vim.keymap.set('n', 'F', M._clear_filter, opts)
  
  -- View options
  vim.keymap.set('n', 'H', M._toggle_hidden_files, opts)
  vim.keymap.set('n', 'I', M._show_file_info, opts)
  
  -- Context menu
  vim.keymap.set('n', '<RightMouse>', M._show_context_menu, opts)
  vim.keymap.set('n', 'C', M._show_context_menu, opts)
  
  -- Refresh
  vim.keymap.set('n', '<F5>', M._refresh_all, opts)
  vim.keymap.set('n', 'g', M._refresh_current, opts)
  
  -- Window operations
  vim.keymap.set('n', 'q', M._close_enhanced, opts)
  vim.keymap.set('n', '<Esc>', M._close_enhanced, opts)
  
  -- Help
  vim.keymap.set('n', '?', M._show_help, opts)
end

--- Create file interactively
function M._create_file_interactive()
  local current_node = M._get_current_node()
  if not current_node then
    return
  end
  
  -- Show file template selection
  local template_names = {}
  for _, template in ipairs(M.FILE_TEMPLATES) do
    table.insert(template_names, template.name)
  end
  
  vim.ui.select(template_names, {
    prompt = 'Select file template:',
  }, function(choice)
    if choice then
      local template = nil
      for _, t in ipairs(M.FILE_TEMPLATES) do
        if t.name == choice then
          template = t
          break
        end
      end
      
      if template then
        M._create_file_from_template(current_node, template)
      end
    end
  end)
end

--- Create project interactively
function M._create_project_interactive()
  -- Show project template selection
  local template_names = {}
  for _, template in ipairs(M.PROJECT_TEMPLATES) do
    table.insert(template_names, template.name)
  end
  
  vim.ui.select(template_names, {
    prompt = 'Select project template:',
  }, function(choice)
    if choice then
      local template = nil
      for _, t in ipairs(M.PROJECT_TEMPLATES) do
        if t.name == choice then
          template = t
          break
        end
      end
      
      if template then
        M._create_project_from_template(template)
      end
    end
  end)
end

--- Create file from template
--- @param parent_node table Parent node
--- @param template table File template
function M._create_file_from_template(parent_node, template)
  local file_name = vim.fn.input("File name: ")
  if file_name == "" then
    return
  end
  
  -- Add extension if not provided
  if not file_name:match("%." .. template.extension .. "$") then
    file_name = file_name .. "." .. template.extension
  end
  
  local parent_path = parent_node.type == M.NODE_TYPES.FOLDER and parent_node.path or vim.fn.fnamemodify(parent_node.path, ':h')
  local file_path = parent_path .. "/" .. file_name
  
  -- Generate file content from template
  local content = M._generate_file_content(template, file_name)
  
  -- Create file
  local success = M._write_file(file_path, content)
  if success then
    logger.info("Created file: " .. file_path)
    M._refresh_tree()
    
    -- Open the new file
    vim.schedule(function()
      vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
    end)
  else
    logger.error("Failed to create file: " .. file_path)
  end
end

--- Create project from template
--- @param template table Project template
function M._create_project_from_template(template)
  local project_name = vim.fn.input("Project name: ")
  if project_name == "" then
    return
  end
  
  local solution_dir = M._get_solution_directory()
  if not solution_dir then
    logger.error("No solution directory found")
    return
  end
  
  local project_dir = solution_dir .. "/" .. project_name
  
  -- Create project using dotnet CLI
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "new", template.template,
    "--name", project_name,
    "--framework", template.framework,
    "--output", project_dir
  }
  
  process.run_async(cmd, {
    on_exit = function(result)
      if result.success then
        logger.info("Created project: " .. project_name)
        
        -- Add project to solution if solution exists
        local solution_file = M._find_solution_file()
        if solution_file then
          M._add_project_to_solution(solution_file, project_dir .. "/" .. project_name .. ".csproj")
        end
        
        M._refresh_tree()
      else
        logger.error("Failed to create project: " .. project_name)
        logger.debug("Error: " .. (result.stderr or "Unknown error"))
      end
    end
  })
end

--- Generate file content from template
--- @param template table File template
--- @param file_name string File name
--- @return string content
function M._generate_file_content(template, file_name)
  local class_name = vim.fn.fnamemodify(file_name, ':r')
  local namespace = M._get_current_namespace()
  
  local templates = {
    class = string.format([[namespace %s;

public class %s
{
    
}]], namespace, class_name),
    
    interface = string.format([[namespace %s;

public interface %s
{
    
}]], namespace, class_name),
    
    enum = string.format([[namespace %s;

public enum %s
{
    
}]], namespace, class_name),
    
    record = string.format([[namespace %s;

public record %s
{
    
}]], namespace, class_name),
    
    controller = string.format([[using Microsoft.AspNetCore.Mvc;

namespace %s.Controllers;

[ApiController]
[Route("api/[controller]")]
public class %s : ControllerBase
{
    
}]], namespace, class_name),
    
    service = string.format([[namespace %s.Services;

public class %s
{
    
}]], namespace, class_name),
    
    model = string.format([[namespace %s.Models;

public class %s
{
    
}]], namespace, class_name),
    
    config = [[{
  
}]]
  }
  
  return templates[template.template] or ""
end

--- Get current namespace based on folder structure
--- @return string namespace
function M._get_current_namespace()
  local current_node = M._get_current_node()
  if not current_node then
    return "MyNamespace"
  end
  
  -- Simple namespace generation based on folder structure
  local project_node = M._find_parent_project(current_node)
  if project_node then
    local project_name = vim.fn.fnamemodify(project_node.path, ':t:r')
    return project_name
  end
  
  return "MyNamespace"
end

--- Find parent project node
--- @param node table Current node
--- @return table|nil project_node
function M._find_parent_project(node)
  -- Implementation would traverse up the tree to find project node
  return nil
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

--- Add project to solution
--- @param solution_file string Solution file path
--- @param project_file string Project file path
function M._add_project_to_solution(solution_file, project_file)
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "sln", solution_file,
    "add", project_file
  }
  
  process.run_async(cmd, {
    on_exit = function(result)
      if result.success then
        logger.info("Added project to solution")
      else
        logger.error("Failed to add project to solution")
      end
    end
  })
end

--- Write file content
--- @param file_path string File path
--- @param content string File content
--- @return boolean success
function M._write_file(file_path, content)
  local file = io.open(file_path, 'w')
  if not file then
    return false
  end
  
  file:write(content)
  file:close()
  return true
end

--- Check if enhanced explorer is open
--- @return boolean is_open
function M._is_open()
  return M._explorer_win and vim.api.nvim_win_is_valid(M._explorer_win)
end

--- Close enhanced explorer
function M._close_enhanced()
  if M._explorer_win and vim.api.nvim_win_is_valid(M._explorer_win) then
    vim.api.nvim_win_close(M._explorer_win, false)
    M._explorer_win = nil
    logger.info("Enhanced solution explorer closed")
  end
end

--- Get current node under cursor
--- @return table|nil current_node
function M._get_current_node()
  if not M._explorer_win then
    return nil
  end
  
  local line = vim.api.nvim_win_get_cursor(M._explorer_win)[1]
  -- Implementation would map line to tree node
  return nil
end

--- Show help
function M._show_help()
  local help_text = {
    "Enhanced Solution Explorer Help",
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
  
  -- Show help in floating window
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_text)
  vim.api.nvim_buf_set_option(help_buf, 'modifiable', false)
  
  local help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = 'editor',
    width = 50,
    height = #help_text + 2,
    col = math.floor((vim.o.columns - 50) / 2),
    row = math.floor((vim.o.lines - #help_text) / 2),
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

--- Placeholder functions for remaining operations
function M._on_enter_enhanced() end
function M._toggle_node_enhanced() end
function M._create_folder_interactive() end
function M._rename_interactive() end
function M._delete_interactive() end
function M._copy_interactive() end
function M._move_interactive() end
function M._add_reference_interactive() end
function M._manage_packages_interactive() end
function M._filter_interactive() end
function M._search_interactive() end
function M._clear_filter() end
function M._toggle_hidden_files() end
function M._show_file_info() end
function M._show_context_menu() end
function M._refresh_all() end
function M._refresh_current() end
function M._load_enhanced_solution(solution_file) end
function M._refresh_project_node(project_file) end
function M._handle_file_created(file_path) end
function M._handle_file_deleted(file_path) end
function M._handle_file_renamed(old_path, new_path) end
function M._show_no_solution_message() end
function M._refresh_tree() end

--- Shutdown enhanced explorer
function M.shutdown()
  if M._initialized then
    M._close_enhanced()
    M._initialized = false
    logger.info("Enhanced solution explorer shutdown")
  end
end

return M
