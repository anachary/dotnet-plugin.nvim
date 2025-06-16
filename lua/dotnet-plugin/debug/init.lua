-- dotnet-plugin.nvim - Debug Integration Module
-- Provides Debug Adapter Protocol (DAP) integration for .NET debugging

local M = {}

-- Import dependencies
local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')
local process = require('dotnet-plugin.core.process')

-- Debug state
M._initialized = false
M._active_sessions = {}
M._breakpoints = {}
M._debug_adapters = {}

--- Setup debug integration
--- @param opts table|nil Configuration options
--- @return boolean success True if setup succeeded
function M.setup(opts)
  if M._initialized then
    return true
  end

  opts = opts or {}
  
  -- Initialize debug adapters
  local success = M._setup_debug_adapters()
  if not success then
    logger.error("Failed to setup debug adapters")
    return false
  end

  -- Setup DAP configuration
  M._setup_dap_configuration()

  -- Register debug commands
  M._register_commands()

  -- Setup event handlers
  M._setup_event_handlers()

  M._initialized = true
  logger.info("Debug integration initialized")
  
  return true
end

--- Setup debug adapters for different .NET runtimes
--- @return boolean success
function M._setup_debug_adapters()
  local adapters = {}
  
  -- .NET Core/5+ adapter (netcoredbg)
  adapters.coreclr = {
    type = 'executable',
    command = 'netcoredbg',
    args = {'--interpreter=vscode'},
    options = {
      detached = false
    }
  }
  
  -- .NET Framework adapter (vsdbg)
  adapters.netfx = {
    type = 'executable', 
    command = 'vsdbg',
    args = {'--interpreter=vscode'},
    options = {
      detached = false
    }
  }

  M._debug_adapters = adapters
  
  -- Check if debug adapters are available
  local has_coreclr = vim.fn.executable('netcoredbg') == 1
  local has_netfx = vim.fn.executable('vsdbg') == 1
  
  if not has_coreclr and not has_netfx then
    logger.warn("No debug adapters found. Install netcoredbg or vsdbg for debugging support")
    return false
  end
  
  if has_coreclr then
    logger.debug("Found netcoredbg debug adapter")
  end
  
  if has_netfx then
    logger.debug("Found vsdbg debug adapter")
  end
  
  return true
end

--- Setup DAP configuration for .NET projects
function M._setup_dap_configuration()
  -- Check if nvim-dap is available
  local dap_ok, dap = pcall(require, 'dap')
  if not dap_ok then
    logger.warn("nvim-dap not found. Debug functionality will be limited")
    return
  end

  -- Configure adapters
  for name, adapter in pairs(M._debug_adapters) do
    dap.adapters[name] = adapter
  end

  -- Configure .NET debug configurations
  dap.configurations.cs = dap.configurations.cs or {}
  dap.configurations.fsharp = dap.configurations.fsharp or {}
  dap.configurations.vb = dap.configurations.vb or {}

  -- Add default configurations
  local default_configs = M._get_default_debug_configurations()
  
  for _, lang in ipairs({'cs', 'fsharp', 'vb'}) do
    for _, config in ipairs(default_configs) do
      table.insert(dap.configurations[lang], config)
    end
  end
  
  logger.debug("DAP configurations setup complete")
end

--- Get default debug configurations for .NET projects
--- @return table configurations
function M._get_default_debug_configurations()
  return {
    {
      type = "coreclr",
      name = "Launch - .NET Core",
      request = "launch",
      program = function()
        return M._get_program_path()
      end,
      cwd = "${workspaceFolder}",
      stopAtEntry = false,
      args = {},
      console = "integratedTerminal",
      env = {
        ASPNETCORE_ENVIRONMENT = "Development"
      }
    },
    {
      type = "coreclr", 
      name = "Attach - .NET Core",
      request = "attach",
      processId = function()
        return M._select_process()
      end
    }
  }
end

--- Get the program path for debugging
--- @return string|nil program_path
function M._get_program_path()
  -- Try to find the current project's output
  local current_file = vim.fn.expand('%:p')
  local project_file = M._find_project_file(current_file)
  
  if not project_file then
    logger.warn("No project file found for debugging")
    return nil
  end
  
  -- Simple path construction (would be enhanced with project parsing)
  local project_dir = vim.fn.fnamemodify(project_file, ':h')
  local project_name = vim.fn.fnamemodify(project_file, ':t:r')
  local bin_path = project_dir .. "/bin/Debug/net8.0/" .. project_name .. ".dll"
  
  -- Check if the binary exists
  if vim.fn.filereadable(bin_path) == 0 then
    logger.warn("Debug binary not found: " .. bin_path .. ". Build the project first.")
    return nil
  end
  
  return bin_path
end

--- Find the project file for a given source file
--- @param file_path string Source file path
--- @return string|nil project_file
function M._find_project_file(file_path)
  local dir = vim.fn.fnamemodify(file_path, ':h')
  
  -- Search upward for project files
  while dir ~= '/' and dir ~= '' do
    local project_files = vim.fn.glob(dir .. '/*.{csproj,fsproj,vbproj}', false, true)
    if #project_files > 0 then
      return project_files[1]
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  
  return nil
end

--- Select a process for attaching debugger
--- @return number|nil process_id
function M._select_process()
  -- Get list of .NET processes
  local processes = M._get_dotnet_processes()
  
  if #processes == 0 then
    logger.warn("No .NET processes found")
    return nil
  end
  
  -- Create selection list
  local items = {}
  for i, proc in ipairs(processes) do
    table.insert(items, string.format("%d: %s (PID: %s)", i, proc.name, proc.pid))
  end
  
  -- Show selection dialog
  local choice = vim.fn.inputlist(vim.list_extend({"Select process:"}, items))
  
  if choice > 0 and choice <= #processes then
    return tonumber(processes[choice].pid)
  end
  
  return nil
end

--- Get list of running .NET processes
--- @return table processes
function M._get_dotnet_processes()
  local processes = {}
  
  -- Use different commands based on OS
  local cmd
  if vim.fn.has('win32') == 1 then
    cmd = {'powershell', '-Command', 'Get-Process | Where-Object {$_.ProcessName -like "*dotnet*"} | Select-Object Id,ProcessName'}
  else
    cmd = {'ps', 'aux'}
  end
  
  local result = process.run_sync(cmd)
  if not result.success then
    logger.error("Failed to get process list")
    return processes
  end
  
  -- Parse process output (simplified)
  for line in result.stdout:gmatch("[^\r\n]+") do
    local pid, name = line:match("(%d+)%s+(.+)")
    if pid and name and (name:find("dotnet") or name:find("%.exe")) then
      table.insert(processes, {pid = pid, name = name})
    end
  end
  
  return processes
end

--- Register debug commands
function M._register_commands()
  -- Debug start command
  vim.api.nvim_create_user_command('DotnetDebugStart', function(opts)
    M.start_debugging(opts.args)
  end, {
    nargs = '?',
    desc = 'Start debugging .NET application'
  })
  
  -- Debug attach command
  vim.api.nvim_create_user_command('DotnetDebugAttach', function()
    M.attach_debugger()
  end, {
    desc = 'Attach debugger to running .NET process'
  })
  
  -- Toggle breakpoint command
  vim.api.nvim_create_user_command('DotnetToggleBreakpoint', function()
    M.toggle_breakpoint()
  end, {
    desc = 'Toggle breakpoint at current line'
  })
  
  -- Debug status command
  vim.api.nvim_create_user_command('DotnetDebugStatus', function()
    M.show_debug_status()
  end, {
    desc = 'Show debug session status'
  })
  
  logger.debug("Debug commands registered")
end

--- Setup event handlers
function M._setup_event_handlers()
  -- Listen for project changes to update debug configurations
  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M._update_debug_configurations(data.project_file)
  end)
  
  logger.debug("Debug event handlers setup")
end

--- Update debug configurations for a project
--- @param project_file string Project file path
function M._update_debug_configurations(project_file)
  logger.debug("Updating debug configurations for project: " .. project_file)
end

--- Start debugging session
--- @param config_name string|nil Debug configuration name
function M.start_debugging(config_name)
  local dap_ok, dap = pcall(require, 'dap')
  if not dap_ok then
    logger.error("nvim-dap not available")
    return
  end
  
  if config_name and config_name ~= "" then
    -- Start with specific configuration
    dap.run(config_name)
  else
    -- Show configuration selection
    dap.continue()
  end
  
  logger.info("Debug session started")
end

--- Attach debugger to running process
function M.attach_debugger()
  local dap_ok, dap = pcall(require, 'dap')
  if not dap_ok then
    logger.error("nvim-dap not available")
    return
  end
  
  -- Use attach configuration
  local attach_config = {
    type = "coreclr",
    name = "Attach",
    request = "attach", 
    processId = M._select_process()
  }
  
  if attach_config.processId then
    dap.run(attach_config)
    logger.info("Debugger attached to process: " .. attach_config.processId)
  end
end

--- Toggle breakpoint at current line
function M.toggle_breakpoint()
  local dap_ok, dap = pcall(require, 'dap')
  if not dap_ok then
    logger.error("nvim-dap not available")
    return
  end
  
  dap.toggle_breakpoint()
  logger.debug("Breakpoint toggled")
end

--- Show debug session status
function M.show_debug_status()
  local dap_ok, dap = pcall(require, 'dap')
  if not dap_ok then
    logger.error("nvim-dap not available")
    return
  end
  
  local session = dap.session()
  if session then
    logger.info("Debug session active: " .. (session.config.name or "Unknown"))
  else
    logger.info("No active debug session")
  end
end

--- Shutdown debug integration
function M.shutdown()
  if M._initialized then
    -- Stop all active sessions
    for _, session in pairs(M._active_sessions) do
      if session.stop then
        session:stop()
      end
    end
    
    M._active_sessions = {}
    M._breakpoints = {}
    M._initialized = false
    
    logger.info("Debug integration shutdown")
  end
end

return M
