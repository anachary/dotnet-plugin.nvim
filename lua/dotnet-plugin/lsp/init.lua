-- dotnet-plugin.nvim - LSP Integration Module
-- Enterprise-optimized Roslyn Language Server integration

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')

-- Import LSP components
local client = require('dotnet-plugin.lsp.client')
local handlers = require('dotnet-plugin.lsp.handlers')
local extensions = require('dotnet-plugin.lsp.extensions')
local intellisense = require('dotnet-plugin.lsp.intellisense')

-- LSP state
local lsp_initialized = false
local active_clients = {}

--- Initialize the LSP system
--- @return boolean success True if LSP was initialized successfully
function M.setup()
  if lsp_initialized then
    return true
  end

  local lsp_config = config.get_value("lsp") or {}
  
  if not lsp_config.enabled then
    logger.info("LSP integration disabled in configuration")
    return true
  end

  logger.info("Initializing LSP integration with Roslyn Language Server")

  -- Initialize LSP components
  local success = true
  
  -- Setup LSP client
  if not client.setup() then
    logger.error("Failed to initialize LSP client")
    success = false
  end

  -- Setup message handlers
  if not handlers.setup() then
    logger.error("Failed to initialize LSP handlers")
    success = false
  end

  -- Setup extensions
  if not extensions.setup() then
    logger.error("Failed to initialize LSP extensions")
    success = false
  end

  -- Setup IntelliSense
  if not intellisense.setup() then
    logger.error("Failed to initialize IntelliSense")
    success = false
  end

  if success then
    lsp_initialized = true
    logger.info("LSP integration initialized successfully")
    
    -- Subscribe to relevant events
    M._setup_event_handlers()
  else
    logger.error("LSP integration initialization failed")
  end

  return success
end

--- Setup event handlers for LSP integration
function M._setup_event_handlers()
  -- Solution events
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M.on_solution_loaded(data)
  end)

  events.subscribe(events.EVENTS.SOLUTION_UNLOADED, function(data)
    M.on_solution_unloaded(data)
  end)

  -- Project events
  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M.on_project_changed(data)
  end)

  -- Buffer events
  events.subscribe(events.EVENTS.BUFFER_OPENED, function(data)
    M.on_buffer_opened(data)
  end)

  events.subscribe(events.EVENTS.BUFFER_CLOSED, function(data)
    M.on_buffer_closed(data)
  end)
end

--- Handle solution loaded event
--- @param data table Solution data
function M.on_solution_loaded(data)
  logger.debug("LSP: Solution loaded", { path = data.path })
  
  -- Configure workspace for the solution
  if data.path then
    client.configure_workspace(data.path, data)
  end
end

--- Handle solution unloaded event
--- @param data table Solution data
function M.on_solution_unloaded(data)
  logger.debug("LSP: Solution unloaded", { path = data.path })
  
  -- Clean up workspace configuration
  if data.path then
    client.cleanup_workspace(data.path)
  end
end

--- Handle project changed event
--- @param data table Project data
function M.on_project_changed(data)
  logger.debug("LSP: Project changed", { path = data.path })
  
  -- Notify LSP client of project changes
  client.notify_project_change(data.path, data)
end

--- Handle buffer opened event
--- @param data table Buffer data
function M.on_buffer_opened(data)
  if not M.is_dotnet_file(data.file) then
    return
  end

  logger.debug("LSP: .NET buffer opened", { file = data.file })
  
  -- Auto-attach LSP client if enabled
  local lsp_config = config.get_value("lsp") or {}
  if lsp_config.auto_attach then
    client.attach_to_buffer(data.buffer, data.file)
  end
end

--- Handle buffer closed event
--- @param data table Buffer data
function M.on_buffer_closed(data)
  if not M.is_dotnet_file(data.file) then
    return
  end

  logger.debug("LSP: .NET buffer closed", { file = data.file })
  
  -- Clean up buffer-specific LSP state
  client.detach_from_buffer(data.buffer, data.file)
end

--- Check if file is a .NET file that should have LSP support
--- @param file_path string File path
--- @return boolean is_dotnet_file True if file should have LSP support
function M.is_dotnet_file(file_path)
  if not file_path then
    return false
  end

  local dotnet_extensions = {
    ".cs", ".fs", ".vb",           -- Source files
    ".csproj", ".fsproj", ".vbproj", -- Project files
    ".sln",                        -- Solution files
    ".razor", ".cshtml"            -- Web files
  }

  for _, ext in ipairs(dotnet_extensions) do
    if vim.endswith(file_path, ext) then
      return true
    end
  end

  return false
end

--- Get LSP status information
--- @return table status LSP status and statistics
function M.status()
  return {
    initialized = lsp_initialized,
    active_clients = vim.tbl_count(active_clients),
    client_status = client.get_status(),
    handlers_status = handlers.get_status(),
    extensions_status = extensions.get_status(),
    intellisense_status = intellisense.get_status()
  }
end

--- Get workspace information
--- @return table workspace_info Current workspace configuration
function M.workspace_info()
  return client.get_workspace_info()
end

--- Restart LSP client
--- @param buffer number|nil Buffer number (default: current buffer)
--- @return boolean success True if restart was successful
function M.restart(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  return client.restart(buffer)
end

--- Install Roslyn Language Server
--- @param method string|nil Installation method (optional)
--- @return boolean success True if installation was successful
function M.install_server(method)
  return client.install_server(method)
end

--- Check if Roslyn Language Server is installed
--- @return boolean installed True if server is available
function M.is_server_installed()
  return client.is_server_installed()
end

--- Ensure Roslyn Language Server is installed
--- @return boolean success True if server is available after ensuring installation
function M.ensure_server_installed()
  return client.ensure_server_installed()
end

--- Check if LSP is initialized
--- @return boolean initialized True if LSP is ready
function M.is_initialized()
  return lsp_initialized
end

--- Shutdown LSP system
function M.shutdown()
  if lsp_initialized then
    logger.info("Shutting down LSP integration")
    
    -- Shutdown components
    intellisense.shutdown()
    extensions.shutdown()
    handlers.shutdown()
    client.shutdown()
    
    -- Clear state
    active_clients = {}
    lsp_initialized = false
    
    logger.info("LSP integration shutdown complete")
  end
end

return M
