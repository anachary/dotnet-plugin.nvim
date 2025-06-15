-- dotnet-plugin.nvim - LSP Client Management
-- Enterprise-optimized Roslyn Language Server client

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')
local solution_parser = require('dotnet-plugin.solution.parser')
local installer = require('dotnet-plugin.lsp.installer')

-- LSP client state
local client_initialized = false
local active_clients = {}
local workspace_folders = {}

--- Initialize the LSP client
--- @return boolean success True if client was initialized successfully
function M.setup()
  if client_initialized then
    return true
  end

  logger.info("Initializing Roslyn Language Server client")

  -- Check if Neovim LSP is available
  if not vim.lsp then
    logger.error("Neovim LSP not available")
    return false
  end

  -- Initialize installer
  installer.setup()

  -- Check if Roslyn Language Server is available (non-blocking)
  local server_available = installer.is_installed()
  if not server_available then
    logger.warn("Roslyn Language Server not found - LSP features will be limited")
    logger.info("Use :DotnetInstallLSP to install the language server")
    -- Continue with setup to allow manual installation later
  else
    logger.info("Roslyn Language Server found and ready")
  end

  -- Setup Roslyn Language Server configuration
  local success = M._setup_roslyn_config()

  if success then
    client_initialized = true
    logger.info("LSP client initialized successfully")
  else
    logger.error("Failed to initialize LSP client")
  end

  return success
end

--- Setup Roslyn Language Server configuration
--- @return boolean success True if configuration was successful
function M._setup_roslyn_config()
  local lsp_config = config.get_value("lsp") or {}

  -- Get the correct path to Roslyn Language Server
  local server_path = installer.get_server_path() or "Microsoft.CodeAnalysis.LanguageServer"

  -- Enterprise-optimized Roslyn configuration
  local roslyn_config = {
    name = "roslyn",
    cmd = { server_path },
    filetypes = { "cs", "vb" },
    root_dir = function(fname)
      -- Use cached solution data for fast workspace detection
      return M._find_solution_root(fname)
    end,
    settings = {
      ["csharp|background_analysis"] = {
        dotnet_analyzer_diagnostics_scope = lsp_config.diagnostics.scope or "fullSolution",
        dotnet_compiler_diagnostics_scope = lsp_config.diagnostics.scope or "fullSolution"
      },
      ["csharp|completion"] = {
        dotnet_provide_regex_completions = lsp_config.completion.enable_regex_completions,
        dotnet_show_completion_items_from_unimported_namespaces = lsp_config.completion.enable_unimported_namespaces
      }
    },
    init_options = {
      -- Enterprise optimization for large solutions
      maxProjectFileCountForDiagnosticAnalysis = lsp_config.performance.max_project_count or 1000,
      enableServerGC = lsp_config.performance.enable_server_gc,
      useServerGC = lsp_config.performance.use_server_gc
    },
    capabilities = M._get_client_capabilities(),
    on_attach = M._on_attach,
    on_init = M._on_init,
    on_exit = M._on_exit
  }

  -- Register the configuration with Neovim LSP
  local lspconfig_ok, lspconfig = pcall(require, 'lspconfig')
  if lspconfig_ok then
    -- Use lspconfig if available
    lspconfig.roslyn = {
      default_config = roslyn_config
    }
    logger.debug("Registered Roslyn config with lspconfig")
  else
    -- Fallback to manual configuration
    vim.lsp.start_client(roslyn_config)
    logger.debug("Started Roslyn client manually")
  end

  return true
end

--- Find solution root directory using cached data
--- @param fname string File name
--- @return string|nil root_dir Solution root directory or nil
function M._find_solution_root(fname)
  if not fname then
    return nil
  end

  -- First try to get from cache for performance
  local cached_root = cache.get_solution_root and cache.get_solution_root(fname)
  if cached_root then
    logger.debug("Found solution root from cache", { file = fname, root = cached_root })
    return cached_root
  end

  -- Fallback to directory traversal
  local dir = vim.fn.fnamemodify(fname, ":p:h")
  local max_depth = config.get_value("solution.search_depth") or 3
  local current_depth = 0

  while dir and current_depth < max_depth do
    -- Look for solution files
    local sln_files = vim.fn.glob(dir .. "/*.sln", false, true)
    if #sln_files > 0 then
      logger.debug("Found solution root", { file = fname, root = dir })
      return dir
    end

    -- Look for project files as fallback
    local proj_files = vim.fn.glob(dir .. "/*.*proj", false, true)
    if #proj_files > 0 then
      logger.debug("Found project root", { file = fname, root = dir })
      return dir
    end

    -- Move up one directory
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break -- Reached filesystem root
    end
    dir = parent
    current_depth = current_depth + 1
  end

  logger.debug("No solution root found", { file = fname })
  return nil
end

--- Get LSP client capabilities
--- @return table capabilities Client capabilities
function M._get_client_capabilities()
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  
  -- Enable additional capabilities for better IntelliSense
  capabilities.textDocument.completion.completionItem.snippetSupport = true
  capabilities.textDocument.completion.completionItem.resolveSupport = {
    properties = { "documentation", "detail", "additionalTextEdits" }
  }
  
  -- Enable workspace folders for multi-project solutions
  capabilities.workspace.workspaceFolders = true
  
  return capabilities
end

--- Handle LSP client attachment
--- @param client table LSP client
--- @param bufnr number Buffer number
function M._on_attach(client, bufnr)
  logger.info("LSP client attached", { 
    client = client.name, 
    buffer = bufnr,
    file = vim.api.nvim_buf_get_name(bufnr)
  })

  -- Store client reference
  active_clients[bufnr] = client

  -- Setup buffer-specific keymaps and options
  M._setup_buffer_config(client, bufnr)

  -- Emit event for other components
  events.emit(events.EVENTS.LSP_ATTACHED, {
    client = client,
    buffer = bufnr,
    file = vim.api.nvim_buf_get_name(bufnr)
  })
end

--- Handle LSP client initialization
--- @param client table LSP client
--- @param initialize_result table Initialization result
function M._on_init(client, initialize_result)
  logger.info("LSP client initialized", { 
    client = client.name,
    server_info = initialize_result.serverInfo
  })

  -- Configure workspace folders if supported
  if client.server_capabilities.workspaceFolders then
    M._configure_workspace_folders(client)
  end
end

--- Handle LSP client exit
--- @param client table LSP client
--- @param exit_code number Exit code
--- @param signal number Signal
function M._on_exit(client, exit_code, signal)
  logger.warn("LSP client exited", { 
    client = client.name,
    exit_code = exit_code,
    signal = signal
  })

  -- Clean up client references
  for bufnr, buf_client in pairs(active_clients) do
    if buf_client.id == client.id then
      active_clients[bufnr] = nil
    end
  end

  -- Emit event for other components
  events.emit(events.EVENTS.LSP_DETACHED, {
    client = client,
    exit_code = exit_code,
    signal = signal
  })
end

--- Setup buffer-specific configuration
--- @param client table LSP client
--- @param bufnr number Buffer number
function M._setup_buffer_config(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Setup basic keymaps (can be customized by user)
  local opts = { noremap = true, silent = true, buffer = bufnr }
  
  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
  vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
  vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
end

--- Configure workspace folders for multi-project solutions
--- @param client table LSP client
function M._configure_workspace_folders(client)
  local lsp_config = config.get_value("lsp") or {}
  
  if not lsp_config.workspace_folders then
    return
  end

  -- Add workspace folders for all known solutions
  for _, folder in ipairs(workspace_folders) do
    client.notify('workspace/didChangeWorkspaceFolders', {
      event = {
        added = { { uri = vim.uri_from_fname(folder), name = folder } },
        removed = {}
      }
    })
  end
end

--- Configure workspace for a solution
--- @param solution_path string Solution file path
--- @param solution_data table Solution data
function M.configure_workspace(solution_path, solution_data)
  local solution_dir = vim.fn.fnamemodify(solution_path, ":p:h")
  
  -- Add to workspace folders
  if not vim.tbl_contains(workspace_folders, solution_dir) then
    table.insert(workspace_folders, solution_dir)
    logger.debug("Added workspace folder", { path = solution_dir })
  end

  -- Notify all active clients
  for _, client in pairs(active_clients) do
    if client.server_capabilities.workspaceFolders then
      client.notify('workspace/didChangeWorkspaceFolders', {
        event = {
          added = { { uri = vim.uri_from_fname(solution_dir), name = solution_dir } },
          removed = {}
        }
      })
    end
  end
end

--- Clean up workspace configuration
--- @param solution_path string Solution file path
function M.cleanup_workspace(solution_path)
  local solution_dir = vim.fn.fnamemodify(solution_path, ":p:h")
  
  -- Remove from workspace folders
  for i, folder in ipairs(workspace_folders) do
    if folder == solution_dir then
      table.remove(workspace_folders, i)
      logger.debug("Removed workspace folder", { path = solution_dir })
      break
    end
  end

  -- Notify all active clients
  for _, client in pairs(active_clients) do
    if client.server_capabilities.workspaceFolders then
      client.notify('workspace/didChangeWorkspaceFolders', {
        event = {
          added = {},
          removed = { { uri = vim.uri_from_fname(solution_dir), name = solution_dir } }
        }
      })
    end
  end
end

--- Attach LSP client to buffer
--- @param bufnr number Buffer number
--- @param file_path string File path
--- @return boolean success True if attachment was successful
function M.attach_to_buffer(bufnr, file_path)
  if active_clients[bufnr] then
    logger.debug("LSP already attached to buffer", { buffer = bufnr })
    return true
  end

  -- Find appropriate client for this buffer
  local clients = vim.lsp.get_active_clients()
  for _, client in ipairs(clients) do
    if client.name == "roslyn" then
      vim.lsp.buf_attach_client(bufnr, client.id)
      logger.debug("Attached LSP client to buffer", { buffer = bufnr, client = client.name })
      return true
    end
  end

  logger.debug("No suitable LSP client found for buffer", { buffer = bufnr })
  return false
end

--- Detach LSP client from buffer
--- @param bufnr number Buffer number
--- @param file_path string File path
function M.detach_from_buffer(bufnr, file_path)
  if active_clients[bufnr] then
    active_clients[bufnr] = nil
    logger.debug("Detached LSP client from buffer", { buffer = bufnr })
  end
end

--- Notify LSP client of project changes
--- @param project_path string Project file path
--- @param project_data table Project data
function M.notify_project_change(project_path, project_data)
  -- Notify all active clients about project changes
  for _, client in pairs(active_clients) do
    if client.notify then
      client.notify('workspace/didChangeWatchedFiles', {
        changes = {
          {
            uri = vim.uri_from_fname(project_path),
            type = 2 -- Changed
          }
        }
      })
    end
  end
end

--- Get client status
--- @return table status Client status information
function M.get_status()
  return {
    initialized = client_initialized,
    active_clients = vim.tbl_count(active_clients),
    workspace_folders = #workspace_folders,
    server_installation = installer.get_status()
  }
end

--- Get workspace information
--- @return table workspace_info Workspace configuration
function M.get_workspace_info()
  return {
    folders = workspace_folders,
    active_clients = vim.tbl_keys(active_clients)
  }
end

--- Restart LSP client
--- @param bufnr number Buffer number
--- @return boolean success True if restart was successful
function M.restart(bufnr)
  local client = active_clients[bufnr]
  if not client then
    logger.warn("No LSP client attached to buffer", { buffer = bufnr })
    return false
  end

  logger.info("Restarting LSP client", { buffer = bufnr, client = client.name })
  
  -- Stop and restart the client
  client.stop()
  vim.defer_fn(function()
    M.attach_to_buffer(bufnr, vim.api.nvim_buf_get_name(bufnr))
  end, 1000)

  return true
end

--- Install Roslyn Language Server
--- @param method string|nil Installation method (optional)
--- @return boolean success True if installation was successful
function M.install_server(method)
  return installer.install(method)
end

--- Check if Roslyn Language Server is installed
--- @return boolean installed True if server is available
function M.is_server_installed()
  return installer.is_installed()
end

--- Ensure Roslyn Language Server is installed
--- @return boolean success True if server is available after ensuring installation
function M.ensure_server_installed()
  return installer.ensure_installed()
end

--- Shutdown LSP client
function M.shutdown()
  if client_initialized then
    logger.info("Shutting down LSP client")

    -- Stop all active clients
    for _, client in pairs(active_clients) do
      client.stop()
    end

    -- Shutdown installer
    installer.shutdown()

    -- Clear state
    active_clients = {}
    workspace_folders = {}
    client_initialized = false

    logger.info("LSP client shutdown complete")
  end
end

return M
