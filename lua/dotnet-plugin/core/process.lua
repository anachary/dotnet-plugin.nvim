-- Process management for dotnet-plugin.nvim
-- Handles asynchronous execution of .NET CLI commands and external tools

local M = {}

local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')

-- Active processes
local active_processes = {}

-- Process counter for unique IDs
local process_counter = 0

--- Process options
--- @class ProcessOptions
--- @field cwd string|nil Working directory
--- @field env table|nil Environment variables
--- @field timeout number|nil Timeout in milliseconds
--- @field on_stdout function|nil Stdout callback
--- @field on_stderr function|nil Stderr callback
--- @field on_exit function|nil Exit callback
--- @field capture_output boolean|nil Whether to capture output

--- Process result
--- @class ProcessResult
--- @field exit_code number Exit code
--- @field stdout string[] Stdout lines
--- @field stderr string[] Stderr lines
--- @field duration number Duration in milliseconds

--- Start a new process
--- @param cmd string|table Command to execute
--- @param opts ProcessOptions|nil Process options
--- @return number Process ID
function M.start(cmd, opts)
  opts = opts or {}
  
  process_counter = process_counter + 1
  local process_id = process_counter
  
  -- Prepare command
  local command = cmd
  if type(cmd) == "table" then
    command = table.concat(cmd, " ")
  end
  
  logger.debug("Starting process", {
    id = process_id,
    command = command,
    cwd = opts.cwd
  })
  
  -- Prepare process data
  local process_data = {
    id = process_id,
    command = command,
    start_time = vim.loop.hrtime(),
    stdout = {},
    stderr = {},
    exit_code = nil,
    handle = nil,
    stdout_handle = nil,
    stderr_handle = nil,
    opts = opts
  }
  
  active_processes[process_id] = process_data
  
  -- Emit process started event
  events.emit(events.EVENTS.PROCESS_STARTED, {
    id = process_id,
    command = command
  })
  
  -- Start the process
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  
  local handle, pid = vim.loop.spawn(
    type(cmd) == "table" and cmd[1] or cmd,
    {
      args = type(cmd) == "table" and vim.list_slice(cmd, 2) or nil,
      stdio = { nil, stdout, stderr },
      cwd = opts.cwd,
      env = opts.env
    },
    function(exit_code, signal)
      -- Process completed
      process_data.exit_code = exit_code
      process_data.duration = (vim.loop.hrtime() - process_data.start_time) / 1000000
      
      -- Close handles
      if stdout then stdout:close() end
      if stderr then stderr:close() end
      
      logger.debug("Process completed", {
        id = process_id,
        exit_code = exit_code,
        duration = process_data.duration
      })
      
      -- Call exit callback
      if opts.on_exit then
        vim.schedule(function()
          opts.on_exit({
            exit_code = exit_code,
            stdout = process_data.stdout,
            stderr = process_data.stderr,
            duration = process_data.duration
          })
        end)
      end
      
      -- Emit completion event
      local event_name = exit_code == 0 and events.EVENTS.PROCESS_COMPLETED or events.EVENTS.PROCESS_FAILED
      events.emit(event_name, {
        id = process_id,
        command = command,
        exit_code = exit_code,
        duration = process_data.duration
      })
      
      -- Remove from active processes
      active_processes[process_id] = nil
    end
  )
  
  if not handle then
    logger.error("Failed to start process", { command = command })
    active_processes[process_id] = nil
    return -1
  end
  
  process_data.handle = handle
  process_data.stdout_handle = stdout
  process_data.stderr_handle = stderr
  
  -- Setup stdout reading
  if stdout then
    stdout:read_start(function(err, data)
      if err then
        logger.error("Stdout read error", { error = err })
        return
      end
      
      if data then
        local lines = vim.split(data, "\n", { plain = true })
        for _, line in ipairs(lines) do
          if line ~= "" then
            table.insert(process_data.stdout, line)
            
            if opts.on_stdout then
              vim.schedule(function()
                opts.on_stdout(line)
              end)
            end
          end
        end
      end
    end)
  end
  
  -- Setup stderr reading
  if stderr then
    stderr:read_start(function(err, data)
      if err then
        logger.error("Stderr read error", { error = err })
        return
      end
      
      if data then
        local lines = vim.split(data, "\n", { plain = true })
        for _, line in ipairs(lines) do
          if line ~= "" then
            table.insert(process_data.stderr, line)
            
            if opts.on_stderr then
              vim.schedule(function()
                opts.on_stderr(line)
              end)
            end
          end
        end
      end
    end)
  end
  
  -- Setup timeout
  if opts.timeout then
    vim.defer_fn(function()
      if active_processes[process_id] then
        logger.warn("Process timeout, killing", { id = process_id })
        M.kill(process_id)
      end
    end, opts.timeout)
  end
  
  return process_id
end

--- Kill a process
--- @param process_id number Process ID
--- @return boolean Success
function M.kill(process_id)
  local process_data = active_processes[process_id]
  if not process_data then
    return false
  end
  
  logger.debug("Killing process", { id = process_id })
  
  if process_data.handle then
    process_data.handle:kill("sigterm")
  end
  
  return true
end

--- Wait for a process to complete
--- @param process_id number Process ID
--- @param timeout number|nil Timeout in milliseconds
--- @return ProcessResult|nil Process result
function M.wait(process_id, timeout)
  local process_data = active_processes[process_id]
  if not process_data then
    return nil
  end
  
  local start_time = vim.loop.hrtime()
  timeout = timeout or 30000 -- 30 seconds default
  
  while active_processes[process_id] do
    vim.wait(100)
    
    if timeout and (vim.loop.hrtime() - start_time) / 1000000 > timeout then
      logger.warn("Wait timeout for process", { id = process_id })
      M.kill(process_id)
      break
    end
  end
  
  return {
    exit_code = process_data.exit_code or -1,
    stdout = process_data.stdout,
    stderr = process_data.stderr,
    duration = process_data.duration or 0
  }
end

--- Get process information
--- @param process_id number Process ID
--- @return table|nil Process information
function M.get_process(process_id)
  return active_processes[process_id]
end

--- Get all active processes
--- @return table Active processes
function M.get_active_processes()
  return active_processes
end

--- Check if a process is running
--- @param process_id number Process ID
--- @return boolean Is running
function M.is_running(process_id)
  return active_processes[process_id] ~= nil
end

--- Execute a command synchronously
--- @param cmd string|table Command to execute
--- @param opts ProcessOptions|nil Process options
--- @return ProcessResult Process result
function M.execute(cmd, opts)
  opts = opts or {}
  opts.capture_output = true
  
  local process_id = M.start(cmd, opts)
  if process_id == -1 then
    return {
      exit_code = -1,
      stdout = {},
      stderr = { "Failed to start process" },
      duration = 0
    }
  end
  
  return M.wait(process_id, opts.timeout)
end

--- Execute a .NET CLI command
--- @param args table Command arguments
--- @param opts ProcessOptions|nil Process options
--- @return ProcessResult Process result
function M.dotnet(args, opts)
  local config = require('dotnet-plugin.core.config').get()
  local cmd = { config.dotnet_path }
  
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end
  
  return M.execute(cmd, opts)
end

--- Execute an MSBuild command
--- @param args table Command arguments
--- @param opts ProcessOptions|nil Process options
--- @return ProcessResult Process result
function M.msbuild(args, opts)
  local config = require('dotnet-plugin.core.config').get()
  local cmd = { config.msbuild_path }
  
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end
  
  return M.execute(cmd, opts)
end

return M
