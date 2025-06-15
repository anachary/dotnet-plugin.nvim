-- dotnet-plugin.nvim - LSP Extensions
-- .NET-specific features and enhancements leveraging Roslyn's enterprise capabilities

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')
local solution_parser = require('dotnet-plugin.solution.parser')

-- Extensions state
local extensions_initialized = false
local custom_commands = {}

--- Initialize LSP extensions
--- @return boolean success True if extensions were initialized successfully
function M.setup()
  if extensions_initialized then
    return true
  end

  logger.info("Initializing .NET-specific LSP extensions")

  -- Setup custom commands
  M._setup_custom_commands()
  
  -- Setup code actions
  M._setup_code_actions()
  
  -- Setup solution-aware features
  M._setup_solution_features()

  extensions_initialized = true
  logger.info("LSP extensions initialized successfully")
  
  return true
end

--- Setup custom .NET commands
function M._setup_custom_commands()
  -- Add using statement command
  vim.api.nvim_create_user_command('DotnetAddUsing', function(opts)
    M.add_using_statement(opts.args)
  end, {
    nargs = 1,
    desc = 'Add using statement to current file'
  })

  -- Organize usings command
  vim.api.nvim_create_user_command('DotnetOrganizeUsings', function()
    M.organize_usings()
  end, {
    desc = 'Organize using statements in current file'
  })

  -- Go to project file command
  vim.api.nvim_create_user_command('DotnetGoToProject', function()
    M.go_to_project_file()
  end, {
    desc = 'Open the project file for current buffer'
  })

  -- Show project dependencies command
  vim.api.nvim_create_user_command('DotnetShowDependencies', function()
    M.show_project_dependencies()
  end, {
    desc = 'Show dependencies for current project'
  })

  -- Find symbol in solution command
  vim.api.nvim_create_user_command('DotnetFindSymbol', function(opts)
    M.find_symbol_in_solution(opts.args)
  end, {
    nargs = 1,
    desc = 'Find symbol across entire solution'
  })

  -- Install Roslyn Language Server command
  vim.api.nvim_create_user_command('DotnetInstallLSP', function(opts)
    M.install_lsp_server(opts.args)
  end, {
    nargs = '?',
    desc = 'Install Roslyn Language Server (optional method: dotnet_tool, manual_download)'
  })

  -- Check LSP server status command
  vim.api.nvim_create_user_command('DotnetLSPStatus', function()
    M.show_lsp_status()
  end, {
    desc = 'Show Roslyn Language Server installation status'
  })

  logger.debug("Custom .NET commands registered")
end

--- Setup enhanced code actions
function M._setup_code_actions()
  -- Register custom code action handler
  local original_code_action = vim.lsp.buf.code_action
  
  vim.lsp.buf.code_action = function(options)
    -- Add .NET-specific code actions
    local enhanced_options = vim.tbl_deep_extend("force", options or {}, {
      context = {
        only = nil, -- Allow all code actions
        diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
      }
    })
    
    -- Call original handler with enhanced options
    original_code_action(enhanced_options)
    
    -- Add our custom actions
    M._add_custom_code_actions()
  end

  logger.debug("Enhanced code actions registered")
end

--- Setup solution-aware features
function M._setup_solution_features()
  -- Subscribe to solution events
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M._on_solution_loaded(data)
  end)

  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M._on_project_changed(data)
  end)
end

--- Add using statement to current file
--- @param namespace string Namespace to add
function M.add_using_statement(namespace)
  if not namespace or namespace == "" then
    logger.warn("No namespace provided for using statement")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- Find the position to insert the using statement
  local insert_line = M._find_using_insert_position(lines)
  
  -- Create the using statement
  local using_statement = "using " .. namespace .. ";"
  
  -- Check if using statement already exists
  for _, line in ipairs(lines) do
    if line:match("^%s*using%s+" .. vim.pesc(namespace) .. "%s*;") then
      logger.info("Using statement already exists", { namespace = namespace })
      return
    end
  end
  
  -- Insert the using statement
  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, { using_statement })
  
  logger.info("Added using statement", { namespace = namespace, line = insert_line })
  
  -- Emit event
  events.emit(events.EVENTS.CODE_MODIFIED, {
    type = "using_added",
    namespace = namespace,
    buffer = bufnr
  })
end

--- Find the appropriate position to insert using statements
--- @param lines table Buffer lines
--- @return number insert_line Line number to insert at (0-based)
function M._find_using_insert_position(lines)
  local last_using_line = -1
  local first_non_comment_line = 0
  
  for i, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    
    -- Skip empty lines and comments
    if trimmed == "" or trimmed:match("^//") or trimmed:match("^/%*") then
      goto continue
    end
    
    -- Check for using statements
    if trimmed:match("^using%s+") then
      last_using_line = i - 1 -- Convert to 0-based
    elseif trimmed:match("^namespace%s+") or trimmed:match("^class%s+") or trimmed:match("^interface%s+") then
      -- Found namespace or class declaration
      break
    elseif first_non_comment_line == 0 then
      first_non_comment_line = i - 1 -- Convert to 0-based
    end
    
    ::continue::
  end
  
  -- Insert after last using statement, or at the beginning
  return math.max(last_using_line + 1, first_non_comment_line)
end

--- Organize using statements in current file
function M.organize_usings()
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Use LSP code action for organizing usings
  vim.lsp.buf.code_action({
    context = {
      only = { "source.organizeImports" },
      diagnostics = {}
    }
  })
  
  logger.info("Organizing using statements")
  
  -- Emit event
  events.emit(events.EVENTS.CODE_MODIFIED, {
    type = "usings_organized",
    buffer = bufnr
  })
end

--- Go to project file for current buffer
function M.go_to_project_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  
  if not file_path or file_path == "" then
    logger.warn("No file path for current buffer")
    return
  end
  
  -- Find project file
  local project_file = M._find_project_file_for_source(file_path)
  
  if project_file then
    vim.cmd("edit " .. vim.fn.fnameescape(project_file))
    logger.info("Opened project file", { project = project_file })
  else
    logger.warn("No project file found for current buffer")
    vim.notify("No project file found for current buffer", vim.log.levels.WARN)
  end
end

--- Find project file for a source file
--- @param source_file string Source file path
--- @return string|nil project_file Project file path or nil
function M._find_project_file_for_source(source_file)
  local dir = vim.fn.fnamemodify(source_file, ":p:h")
  local max_depth = 3
  local current_depth = 0
  
  while dir and current_depth < max_depth do
    local proj_files = vim.fn.glob(dir .. "/*.*proj", false, true)
    
    if #proj_files > 0 then
      return proj_files[1] -- Return first project file found
    end
    
    -- Move up one directory
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break -- Reached filesystem root
    end
    dir = parent
    current_depth = current_depth + 1
  end
  
  return nil
end

--- Show project dependencies for current buffer
function M.show_project_dependencies()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  
  if not file_path or file_path == "" then
    logger.warn("No file path for current buffer")
    return
  end
  
  -- Find project file
  local project_file = M._find_project_file_for_source(file_path)
  
  if not project_file then
    logger.warn("No project file found for current buffer")
    vim.notify("No project file found for current buffer", vim.log.levels.WARN)
    return
  end
  
  -- Get project data from cache or parse
  local project_data = cache.get_project(project_file)
  if not project_data then
    local project_parser = require('dotnet-plugin.project.parser')
    project_data = project_parser.parse_project(project_file)
  end
  
  if not project_data then
    logger.error("Failed to parse project file", { project = project_file })
    vim.notify("Failed to parse project file", vim.log.levels.ERROR)
    return
  end
  
  -- Display dependencies
  M._display_project_dependencies(project_data)
end

--- Display project dependencies in a floating window
--- @param project_data table Project data
function M._display_project_dependencies(project_data)
  local dependencies = project_data.package_references or {}
  local project_refs = project_data.project_references or {}
  
  local lines = {
    "# Project Dependencies",
    "",
    "## Package References (" .. #dependencies .. ")",
    ""
  }
  
  for _, dep in ipairs(dependencies) do
    table.insert(lines, "- " .. dep.name .. " (" .. (dep.version or "latest") .. ")")
  end
  
  table.insert(lines, "")
  table.insert(lines, "## Project References (" .. #project_refs .. ")")
  table.insert(lines, "")
  
  for _, ref in ipairs(project_refs) do
    table.insert(lines, "- " .. (ref.name or ref.path))
  end
  
  -- Create floating window
  local width = 60
  local height = math.min(#lines + 2, 20)
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Project Dependencies ',
    title_pos = 'center'
  })
  
  -- Close on escape
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<cr>', { noremap = true, silent = true })
  
  logger.info("Displayed project dependencies", { 
    project = project_data.name,
    packages = #dependencies,
    projects = #project_refs
  })
end

--- Find symbol across entire solution
--- @param symbol_name string Symbol name to search for
function M.find_symbol_in_solution(symbol_name)
  if not symbol_name or symbol_name == "" then
    logger.warn("No symbol name provided")
    return
  end

  -- Use LSP workspace symbol search
  vim.lsp.buf.workspace_symbol(symbol_name)

  logger.info("Searching for symbol in solution", { symbol = symbol_name })
end

--- Install Roslyn Language Server
--- @param method string|nil Installation method
function M.install_lsp_server(method)
  local lsp = require('dotnet-plugin.lsp')

  vim.notify("Installing Roslyn Language Server...", vim.log.levels.INFO)

  local success = lsp.install_server(method)

  if success then
    vim.notify("Roslyn Language Server installed successfully!", vim.log.levels.INFO)
    vim.notify("Restart Neovim or run :DotnetLSPStatus to verify installation", vim.log.levels.INFO)
  else
    vim.notify("Failed to install Roslyn Language Server. Check logs for details.", vim.log.levels.ERROR)
    vim.notify("Try manual installation: dotnet tool install --global Microsoft.CodeAnalysis.LanguageServer", vim.log.levels.INFO)
  end
end

--- Show LSP server installation status
function M.show_lsp_status()
  local lsp = require('dotnet-plugin.lsp')
  local status = lsp.status()

  local lines = {
    "# Roslyn Language Server Status",
    "",
    "## Installation Status",
    ""
  }

  local server_status = status.client_status.server_installation
  if server_status then
    table.insert(lines, "- **Installed**: " .. (server_status.installed and "✅ Yes" or "❌ No"))
    if server_status.installed then
      table.insert(lines, "- **Path**: " .. (server_status.path or "Unknown"))
      table.insert(lines, "- **Version**: " .. (server_status.version or "Unknown"))
      table.insert(lines, "- **Method**: " .. (server_status.installation_method or "Unknown"))
    end
  else
    table.insert(lines, "- **Status**: ❌ Installation status unknown")
  end

  table.insert(lines, "")
  table.insert(lines, "## LSP Client Status")
  table.insert(lines, "")
  table.insert(lines, "- **Initialized**: " .. (status.initialized and "✅ Yes" or "❌ No"))
  table.insert(lines, "- **Active Clients**: " .. (status.active_clients or 0))

  if not server_status or not server_status.installed then
    table.insert(lines, "")
    table.insert(lines, "## Installation Commands")
    table.insert(lines, "")
    table.insert(lines, "```bash")
    table.insert(lines, "# Automatic installation")
    table.insert(lines, ":DotnetInstallLSP")
    table.insert(lines, "")
    table.insert(lines, "# Manual installation")
    table.insert(lines, "dotnet tool install --global Microsoft.CodeAnalysis.LanguageServer")
    table.insert(lines, "```")
  end

  -- Create floating window
  local width = 60
  local height = math.min(#lines + 2, 20)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' LSP Server Status ',
    title_pos = 'center'
  })

  -- Close on escape
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<cr>', { noremap = true, silent = true })

  logger.info("Displayed LSP server status")
end

--- Add custom code actions
function M._add_custom_code_actions()
  -- This would be called to add .NET-specific code actions
  -- Implementation depends on specific needs and LSP capabilities
  logger.debug("Adding custom .NET code actions")
end

--- Handle solution loaded event
--- @param solution_data table Solution data
function M._on_solution_loaded(solution_data)
  logger.debug("LSP Extensions: Solution loaded", { 
    solution = solution_data.name,
    projects = #(solution_data.projects or {})
  })
  
  -- Update extension context with solution data
  M.current_solution = solution_data
end

--- Handle project changed event
--- @param project_data table Project data
function M._on_project_changed(project_data)
  logger.debug("LSP Extensions: Project changed", { 
    project = project_data.name or project_data.path
  })
  
  -- Refresh project-specific features
  M._refresh_project_features(project_data)
end

--- Refresh project-specific features
--- @param project_data table Project data
function M._refresh_project_features(project_data)
  -- Invalidate cached project data to force refresh
  if cache.invalidate then
    cache.invalidate(project_data.path)
  end
  
  logger.debug("Refreshed project features", { project = project_data.path })
end

--- Get extensions status
--- @return table status Extensions status information
function M.get_status()
  return {
    initialized = extensions_initialized,
    custom_commands = vim.tbl_count(custom_commands),
    current_solution = M.current_solution and M.current_solution.name or nil
  }
end

--- Shutdown LSP extensions
function M.shutdown()
  if extensions_initialized then
    logger.info("Shutting down LSP extensions")

    -- Remove custom commands
    pcall(vim.api.nvim_del_user_command, 'DotnetAddUsing')
    pcall(vim.api.nvim_del_user_command, 'DotnetOrganizeUsings')
    pcall(vim.api.nvim_del_user_command, 'DotnetGoToProject')
    pcall(vim.api.nvim_del_user_command, 'DotnetShowDependencies')
    pcall(vim.api.nvim_del_user_command, 'DotnetFindSymbol')
    pcall(vim.api.nvim_del_user_command, 'DotnetInstallLSP')
    pcall(vim.api.nvim_del_user_command, 'DotnetLSPStatus')

    -- Clear state
    custom_commands = {}
    M.current_solution = nil
    extensions_initialized = false

    logger.info("LSP extensions shutdown complete")
  end
end

return M
