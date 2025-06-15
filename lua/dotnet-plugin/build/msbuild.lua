-- MSBuild integration for dotnet-plugin.nvim
-- Handles MSBuild command execution and output parsing

local M = {}

local config = require('dotnet-plugin.core.config')
local process = require('dotnet-plugin.core.process')
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

-- MSBuild state
local msbuild_initialized = false
local active_processes = {}

--- Setup MSBuild integration
--- @return boolean success True if MSBuild was initialized successfully
function M.setup()
  if msbuild_initialized then
    return true
  end

  logger.debug("Initializing MSBuild integration")

  -- Verify MSBuild availability
  if not M._verify_msbuild() then
    logger.error("MSBuild not found or not accessible")
    return false
  end

  msbuild_initialized = true
  logger.debug("MSBuild integration initialized")
  
  return true
end

--- Verify MSBuild availability
--- @return boolean True if MSBuild is available
function M._verify_msbuild()
  local build_config = config.get_value("build") or {}
  local msbuild_path = build_config.msbuild_path or "dotnet"
  
  -- Test MSBuild availability
  local result = process.execute({ msbuild_path, "--version" }, {
    timeout = 5000,
    capture_output = true
  })
  
  if result.exit_code == 0 then
    logger.debug("MSBuild verified", { path = msbuild_path })
    return true
  else
    logger.error("MSBuild verification failed", { 
      path = msbuild_path, 
      exit_code = result.exit_code 
    })
    return false
  end
end

--- Build solution or project
--- @param target string Target path (solution or project file)
--- @param opts table|nil Build options
--- @return table|nil Build result with process_id
function M.build(target, opts)
  opts = opts or {}
  
  local build_config = config.get_value("build") or {}
  local args = M._build_args("build", target, opts)
  
  logger.info("Starting MSBuild build", { target = target, args = args })
  
  return M._execute_msbuild(args, opts)
end

--- Rebuild solution or project
--- @param target string Target path
--- @param opts table|nil Build options
--- @return table|nil Build result with process_id
function M.rebuild(target, opts)
  opts = opts or {}
  
  local args = M._build_args("rebuild", target, opts)
  
  logger.info("Starting MSBuild rebuild", { target = target, args = args })
  
  return M._execute_msbuild(args, opts)
end

--- Clean solution or project
--- @param target string Target path
--- @param opts table|nil Build options
--- @return table|nil Build result with process_id
function M.clean(target, opts)
  opts = opts or {}
  
  local args = M._build_args("clean", target, opts)
  
  logger.info("Starting MSBuild clean", { target = target, args = args })
  
  return M._execute_msbuild(args, opts)
end

--- Restore NuGet packages
--- @param target string Target path
--- @param opts table|nil Build options
--- @return table|nil Build result with process_id
function M.restore(target, opts)
  opts = opts or {}
  
  local build_config = config.get_value("build") or {}
  local msbuild_path = build_config.msbuild_path or "dotnet"
  
  local args = { "restore", target }
  
  -- Add configuration if specified
  if opts.configuration then
    table.insert(args, "--configuration")
    table.insert(args, opts.configuration)
  end
  
  -- Add verbosity
  local verbosity = opts.verbosity or build_config.verbosity or "minimal"
  table.insert(args, "--verbosity")
  table.insert(args, verbosity)
  
  logger.info("Starting package restore", { target = target, args = args })
  
  return M._execute_dotnet(args, opts)
end

--- Build command arguments
--- @param operation string Build operation (build, rebuild, clean)
--- @param target string Target path
--- @param opts table Build options
--- @return table Command arguments
function M._build_args(operation, target, opts)
  local build_config = config.get_value("build") or {}
  local args = { operation, target }
  
  -- Add configuration
  local configuration = opts.configuration or build_config.configuration or "Debug"
  table.insert(args, "--configuration")
  table.insert(args, configuration)
  
  -- Add platform if specified
  if opts.platform or build_config.platform then
    table.insert(args, "--platform")
    table.insert(args, opts.platform or build_config.platform)
  end
  
  -- Add verbosity
  local verbosity = opts.verbosity or build_config.verbosity or "minimal"
  table.insert(args, "--verbosity")
  table.insert(args, verbosity)
  
  -- Add parallel builds
  if build_config.max_parallel_builds and build_config.max_parallel_builds > 1 then
    table.insert(args, "--maxcpucount:" .. build_config.max_parallel_builds)
  end
  
  -- Add no-restore if configured
  if build_config.no_restore then
    table.insert(args, "--no-restore")
  end
  
  -- Add additional properties
  if opts.properties then
    for key, value in pairs(opts.properties) do
      table.insert(args, string.format("--property:%s=%s", key, value))
    end
  end
  
  return args
end

--- Execute MSBuild command
--- @param args table Command arguments
--- @param opts table Execution options
--- @return table|nil Result with process_id
function M._execute_msbuild(args, opts)
  local build_config = config.get_value("build") or {}
  local msbuild_path = build_config.msbuild_path or "dotnet"
  
  return M._execute_build_command(msbuild_path, args, opts)
end

--- Execute dotnet command
--- @param args table Command arguments
--- @param opts table Execution options
--- @return table|nil Result with process_id
function M._execute_dotnet(args, opts)
  return M._execute_build_command("dotnet", args, opts)
end

--- Execute build command
--- @param command string Command to execute
--- @param args table Command arguments
--- @param opts table Execution options
--- @return table|nil Result with process_id
function M._execute_build_command(command, args, opts)
  local full_command = { command }
  for _, arg in ipairs(args) do
    table.insert(full_command, arg)
  end
  
  local process_opts = {
    cwd = opts.cwd or vim.fn.getcwd(),
    on_stdout = function(line)
      M._handle_build_output(opts.build_id, "stdout", line, opts)
    end,
    on_stderr = function(line)
      M._handle_build_output(opts.build_id, "stderr", line, opts)
    end,
    on_exit = function(result)
      M._handle_build_exit(opts.build_id, result, opts)
    end
  }
  
  local process_id = process.start(full_command, process_opts)
  
  if process_id and process_id > 0 then
    active_processes[opts.build_id] = {
      process_id = process_id,
      command = full_command,
      start_time = os.time()
    }
    
    return { process_id = process_id }
  else
    logger.error("Failed to start build process", { command = full_command })
    return nil
  end
end

--- Handle build output
--- @param build_id number Build ID
--- @param stream string Output stream (stdout/stderr)
--- @param line string Output line
--- @param opts table Build options
function M._handle_build_output(build_id, stream, line, opts)
  if not line or line == "" then
    return
  end
  
  logger.debug("Build output", { 
    build_id = build_id, 
    stream = stream, 
    line = line 
  })
  
  -- Parse progress information
  local progress_info = M._parse_progress(line)
  if progress_info and opts.on_progress then
    opts.on_progress(progress_info)
  end
  
  -- Parse error/warning information
  local error_info = M._parse_error(line)
  if error_info and opts.on_error then
    opts.on_error(error_info)
  end
  
  -- Emit build progress event
  events.emit(events.EVENTS.BUILD_PROGRESS, {
    build_id = build_id,
    stream = stream,
    line = line,
    progress = progress_info,
    error = error_info
  })
end

--- Handle build process exit
--- @param build_id number Build ID
--- @param result table Process result
--- @param opts table Build options
function M._handle_build_exit(build_id, result, opts)
  local process_info = active_processes[build_id]
  if process_info then
    process_info.end_time = os.time()
    process_info.duration = process_info.end_time - process_info.start_time
  end
  
  local success = result.exit_code == 0
  
  logger.info("Build process completed", {
    build_id = build_id,
    exit_code = result.exit_code,
    success = success,
    duration = process_info and process_info.duration
  })
  
  local build_result = {
    success = success,
    exit_code = result.exit_code,
    stdout = result.stdout,
    stderr = result.stderr,
    duration = process_info and process_info.duration
  }
  
  if not success then
    build_result.error = M._extract_error_summary(result.stderr)
  end
  
  if opts.on_complete then
    opts.on_complete(build_result)
  end
  
  -- Clean up
  active_processes[build_id] = nil
end

--- Parse progress information from build output
--- @param line string Output line
--- @return table|nil Progress information
function M._parse_progress(line)
  -- Parse MSBuild progress patterns
  local patterns = {
    -- "Building project 'ProjectName' (1 of 5)"
    "Building project '([^']+)' %((%d+) of (%d+)%)",
    -- "Build succeeded."
    "Build succeeded%.",
    -- "Build FAILED."
    "Build FAILED%."
  }
  
  for _, pattern in ipairs(patterns) do
    local matches = { string.match(line, pattern) }
    if #matches > 0 then
      if #matches == 3 then
        -- Project progress
        return {
          type = "project",
          project = matches[1],
          current = tonumber(matches[2]),
          total = tonumber(matches[3]),
          percentage = math.floor((tonumber(matches[2]) / tonumber(matches[3])) * 100)
        }
      elseif string.match(line, "Build succeeded%.") then
        return { type = "completed", status = "success" }
      elseif string.match(line, "Build FAILED%.") then
        return { type = "completed", status = "failed" }
      end
    end
  end
  
  return nil
end

--- Parse error/warning information from build output
--- @param line string Output line
--- @return table|nil Error information
function M._parse_error(line)
  -- Parse MSBuild error/warning patterns
  local patterns = {
    -- "file.cs(10,5): error CS1234: Error message"
    "([^%(]+)%((%d+),(%d+)%):%s*(%w+)%s+([^:]+):%s*(.+)",
    -- "error CS1234: Error message"
    "(%w+)%s+([^:]+):%s*(.+)"
  }
  
  for _, pattern in ipairs(patterns) do
    local matches = { string.match(line, pattern) }
    if #matches > 0 then
      if #matches == 6 then
        -- File-based error/warning
        return {
          file = matches[1],
          line = tonumber(matches[2]),
          column = tonumber(matches[3]),
          severity = matches[4]:lower(),
          code = matches[5],
          message = matches[6]
        }
      elseif #matches == 3 then
        -- General error/warning
        return {
          severity = matches[1]:lower(),
          code = matches[2],
          message = matches[3]
        }
      end
    end
  end
  
  return nil
end

--- Extract error summary from stderr
--- @param stderr table Error output lines
--- @return string Error summary
function M._extract_error_summary(stderr)
  if not stderr or #stderr == 0 then
    return "Build failed with unknown error"
  end
  
  -- Look for build failure summary
  for _, line in ipairs(stderr) do
    if string.match(line, "Build FAILED") then
      return line
    end
  end
  
  -- Return first non-empty error line
  for _, line in ipairs(stderr) do
    if line and line:trim() ~= "" then
      return line
    end
  end
  
  return "Build failed"
end

--- Cancel build
--- @param build_id number Build ID
--- @return boolean True if build was cancelled
function M.cancel_build(build_id)
  local process_info = active_processes[build_id]
  if not process_info then
    return false
  end
  
  local success = process.kill(process_info.process_id)
  if success then
    active_processes[build_id] = nil
    logger.info("Build cancelled", { build_id = build_id })
  end
  
  return success
end

--- Get active builds
--- @return table Active build processes
function M.get_active_builds()
  return vim.deepcopy(active_processes)
end

--- Shutdown MSBuild integration
function M.shutdown()
  if msbuild_initialized then
    -- Cancel all active builds
    for build_id, _ in pairs(active_processes) do
      M.cancel_build(build_id)
    end
    
    active_processes = {}
    msbuild_initialized = false
    logger.debug("MSBuild integration shutdown")
  end
end

return M
