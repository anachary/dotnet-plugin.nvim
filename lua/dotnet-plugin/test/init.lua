-- dotnet-plugin.nvim - Test Framework Module
-- Provides test discovery, execution, and reporting for .NET test frameworks

local M = {}

-- Import dependencies
local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')
local process = require('dotnet-plugin.core.process')

-- Test state
M._initialized = false
M._discovered_tests = {}
M._test_results = {}
M._running_tests = {}

-- Supported test frameworks
M.FRAMEWORKS = {
  XUNIT = "xunit",
  NUNIT = "nunit", 
  MSTEST = "mstest"
}

--- Setup test framework integration
--- @param opts table|nil Configuration options
--- @return boolean success True if setup succeeded
function M.setup(opts)
  if M._initialized then
    return true
  end

  opts = opts or {}
  
  -- Register test commands
  M._register_commands()

  -- Setup event handlers
  M._setup_event_handlers()

  -- Discover tests in current workspace
  vim.schedule(function()
    M.discover_tests()
  end)

  M._initialized = true
  logger.info("Test framework initialized")
  
  return true
end

--- Register test commands
function M._register_commands()
  -- Discover tests command
  vim.api.nvim_create_user_command('DotnetTestDiscover', function()
    M.discover_tests()
  end, {
    desc = 'Discover all tests in solution'
  })
  
  -- Run all tests command
  vim.api.nvim_create_user_command('DotnetTestRunAll', function()
    M.run_all_tests()
  end, {
    desc = 'Run all tests in solution'
  })
  
  -- Run tests in current file
  vim.api.nvim_create_user_command('DotnetTestRunFile', function()
    M.run_tests_in_file()
  end, {
    desc = 'Run tests in current file'
  })
  
  -- Run test at cursor
  vim.api.nvim_create_user_command('DotnetTestRunCursor', function()
    M.run_test_at_cursor()
  end, {
    desc = 'Run test at cursor position'
  })
  
  -- Show test results
  vim.api.nvim_create_user_command('DotnetTestResults', function()
    M.show_test_results()
  end, {
    desc = 'Show test results'
  })
  
  -- Test coverage command
  vim.api.nvim_create_user_command('DotnetTestCoverage', function()
    M.run_coverage_analysis()
  end, {
    desc = 'Run test coverage analysis'
  })
  
  logger.debug("Test commands registered")
end

--- Setup event handlers
function M._setup_event_handlers()
  -- Listen for solution changes to rediscover tests
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M.discover_tests()
  end)
  
  -- Listen for project changes
  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M._discover_tests_in_project(data.project_file)
  end)
  
  logger.debug("Test event handlers setup")
end

--- Discover all tests in the current workspace
function M.discover_tests()
  logger.info("Discovering tests...")
  
  -- Clear previous discoveries
  M._discovered_tests = {}
  
  -- Find solution file
  local solution_file = M._find_solution_file()
  if solution_file then
    M._discover_tests_in_solution(solution_file)
  else
    -- No solution, look for individual projects
    M._discover_tests_in_directory(vim.fn.getcwd())
  end
  
  logger.info("Test discovery completed. Found " .. #M._discovered_tests .. " tests")
  
  -- Emit event
  events.emit(events.EVENTS.TESTS_DISCOVERED, {
    count = #M._discovered_tests,
    tests = M._discovered_tests
  })
end

--- Find solution file in current directory or parent directories
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

--- Discover tests in a solution
--- @param solution_file string Solution file path
function M._discover_tests_in_solution(solution_file)
  -- Simple implementation - would parse solution file in real implementation
  local solution_dir = vim.fn.fnamemodify(solution_file, ':h')
  M._discover_tests_in_directory(solution_dir)
end

--- Discover tests in a project
--- @param project_file string Project file path
function M._discover_tests_in_project(project_file)
  -- Check if project has test framework references
  local test_framework = M._detect_test_framework(project_file)
  if not test_framework then
    logger.debug("No test framework detected in project: " .. project_file)
    return
  end
  
  logger.debug("Detected test framework '" .. test_framework .. "' in project: " .. project_file)
  
  -- Use dotnet test --list-tests to discover tests
  local project_dir = vim.fn.fnamemodify(project_file, ':h')
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "test",
    project_file,
    "--list-tests",
    "--verbosity", "quiet"
  }
  
  process.run_async(cmd, {
    cwd = project_dir,
    on_exit = function(result)
      if result.success then
        M._parse_test_list(result.stdout, project_file, test_framework)
      else
        logger.warn("Failed to discover tests in project: " .. project_file)
        logger.debug("Error: " .. (result.stderr or "Unknown error"))
      end
    end
  })
end

--- Discover tests in a directory (recursive)
--- @param directory string Directory path
function M._discover_tests_in_directory(directory)
  local project_files = vim.fn.glob(directory .. '/**/*.{csproj,fsproj,vbproj}', false, true)
  
  for _, project_file in ipairs(project_files) do
    M._discover_tests_in_project(project_file)
  end
end

--- Detect test framework used in a project
--- @param project_file string Project file path
--- @return string|nil framework
function M._detect_test_framework(project_file)
  -- Simple detection based on file content
  local content = table.concat(vim.fn.readfile(project_file) or {}, '\n')
  
  if content:find("xunit") or content:find("xUnit") then
    return M.FRAMEWORKS.XUNIT
  elseif content:find("nunit") or content:find("NUnit") then
    return M.FRAMEWORKS.NUNIT
  elseif content:find("mstest") or content:find("MSTest") then
    return M.FRAMEWORKS.MSTEST
  end
  
  return nil
end

--- Parse test list output from dotnet test --list-tests
--- @param output string Command output
--- @param project_file string Project file path
--- @param framework string Test framework
function M._parse_test_list(output, project_file, framework)
  local tests = {}
  
  -- Parse test names from output
  for line in output:gmatch("[^\r\n]+") do
    line = line:trim and line:trim() or line
    
    -- Skip empty lines and headers
    if line ~= "" and not line:find("^The following Tests are available:") then
      -- Extract test information
      local test_name = line
      local class_name, method_name = test_name:match("(.+)%.([^%.]+)$")
      
      if class_name and method_name then
        table.insert(tests, {
          name = test_name,
          class = class_name,
          method = method_name,
          project = project_file,
          framework = framework,
          status = "not_run"
        })
      end
    end
  end
  
  -- Add to discovered tests
  for _, test in ipairs(tests) do
    table.insert(M._discovered_tests, test)
  end
  
  logger.debug("Discovered " .. #tests .. " tests in project: " .. project_file)
end

--- Run all tests in the solution
function M.run_all_tests()
  logger.info("Running all tests...")
  
  local solution_file = M._find_solution_file()
  local target = solution_file or vim.fn.getcwd()
  
  M._run_tests(target, "all")
end

--- Run tests in current file
function M.run_tests_in_file()
  local current_file = vim.fn.expand('%:p')
  
  -- Find tests in current file
  local file_tests = {}
  for _, test in ipairs(M._discovered_tests) do
    if M._test_belongs_to_file(test, current_file) then
      table.insert(file_tests, test)
    end
  end
  
  if #file_tests == 0 then
    logger.warn("No tests found in current file")
    return
  end
  
  logger.info("Running " .. #file_tests .. " tests in current file...")
  
  -- Run tests with filter
  local test_filter = M._create_test_filter(file_tests)
  M._run_tests_with_filter(test_filter)
end

--- Run test at cursor position
function M.run_test_at_cursor()
  local current_file = vim.fn.expand('%:p')
  local cursor_line = vim.fn.line('.')
  
  -- Find test at cursor position
  local test = M._find_test_at_position(current_file, cursor_line)
  if not test then
    logger.warn("No test found at cursor position")
    return
  end
  
  logger.info("Running test: " .. test.name)
  
  -- Run specific test
  M._run_tests_with_filter(test.name)
end

--- Check if a test belongs to a specific file
--- @param test table Test information
--- @param file_path string File path
--- @return boolean belongs
function M._test_belongs_to_file(test, file_path)
  -- This is a simplified implementation
  local file_name = vim.fn.fnamemodify(file_path, ':t:r')
  return test.class:find(file_name) ~= nil
end

--- Find test at specific position in file
--- @param file_path string File path
--- @param line_number number Line number
--- @return table|nil test
function M._find_test_at_position(file_path, line_number)
  -- This is a simplified implementation
  local file_tests = {}
  for _, test in ipairs(M._discovered_tests) do
    if M._test_belongs_to_file(test, file_path) then
      table.insert(file_tests, test)
    end
  end
  
  -- Return first test (simplified)
  return file_tests[1]
end

--- Create test filter for multiple tests
--- @param tests table List of tests
--- @return string filter
function M._create_test_filter(tests)
  local filters = {}
  for _, test in ipairs(tests) do
    table.insert(filters, test.name)
  end
  return table.concat(filters, "|")
end

--- Run tests with filter
--- @param filter string Test filter
function M._run_tests_with_filter(filter)
  local solution_file = M._find_solution_file()
  local target = solution_file or vim.fn.getcwd()
  
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "test",
    target,
    "--filter", filter,
    "--logger", "trx",
    "--verbosity", "normal"
  }
  
  M._execute_test_command(cmd, filter)
end

--- Run tests on a target (solution/project/directory)
--- @param target string Target path
--- @param scope string Test scope description
function M._run_tests(target, scope)
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "test",
    target,
    "--logger", "trx",
    "--verbosity", "normal"
  }
  
  M._execute_test_command(cmd, scope)
end

--- Execute test command
--- @param cmd table Command array
--- @param scope string Test scope description
function M._execute_test_command(cmd, scope)
  -- Clear previous results for this scope
  M._test_results[scope] = {
    status = "running",
    start_time = os.time(),
    tests = {}
  }
  
  -- Emit test started event
  events.emit(events.EVENTS.TESTS_STARTED, {
    scope = scope,
    command = table.concat(cmd, " ")
  })
  
  process.run_async(cmd, {
    on_stdout = function(data)
      -- Process real-time test output
      M._process_test_output(data, scope)
    end,
    on_exit = function(result)
      M._process_test_completion(result, scope)
    end
  })
end

--- Process real-time test output
--- @param data string Output data
--- @param scope string Test scope
function M._process_test_output(data, scope)
  -- Parse test output for progress updates
  for line in data:gmatch("[^\r\n]+") do
    if line:find("Passed!") or line:find("Failed!") or line:find("Skipped!") then
      logger.debug("Test output: " .. line)
    end
  end
end

--- Process test completion
--- @param result table Command result
--- @param scope string Test scope
function M._process_test_completion(result, scope)
  local test_result = M._test_results[scope]
  test_result.end_time = os.time()
  test_result.duration = test_result.end_time - test_result.start_time
  test_result.success = result.success
  test_result.exit_code = result.exit_code
  test_result.stdout = result.stdout
  test_result.stderr = result.stderr
  
  if result.success then
    test_result.status = "passed"
    logger.info("Tests completed successfully (scope: " .. scope .. ")")
  else
    test_result.status = "failed"
    logger.warn("Tests failed (scope: " .. scope .. ")")
  end
  
  -- Emit test completed event
  events.emit(events.EVENTS.TESTS_COMPLETED, {
    scope = scope,
    result = test_result
  })
end

--- Show test results
function M.show_test_results()
  if vim.tbl_isempty(M._test_results) then
    logger.info("No test results available. Run tests first.")
    return
  end
  
  -- Create results summary
  local summary = {}
  table.insert(summary, "=== Test Results Summary ===")
  
  for scope, result in pairs(M._test_results) do
    table.insert(summary, "")
    table.insert(summary, "Scope: " .. scope)
    table.insert(summary, "Status: " .. result.status)
    table.insert(summary, "Duration: " .. (result.duration or 0) .. "s")
    
    if result.stderr and result.stderr ~= "" then
      table.insert(summary, "Errors:")
      table.insert(summary, result.stderr)
    end
  end
  
  -- Display in new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, summary)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'dotnet-test-results')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  -- Open in split window
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, buf)
  
  logger.info("Test results displayed")
end

--- Run test coverage analysis
function M.run_coverage_analysis()
  logger.info("Running test coverage analysis...")
  
  local solution_file = M._find_solution_file()
  local target = solution_file or vim.fn.getcwd()
  
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "test",
    target,
    "--collect", "XPlat Code Coverage",
    "--verbosity", "normal"
  }
  
  process.run_async(cmd, {
    on_exit = function(result)
      if result.success then
        logger.info("Coverage analysis completed")
        M._process_coverage_results()
      else
        logger.error("Coverage analysis failed")
        logger.debug("Error: " .. (result.stderr or "Unknown error"))
      end
    end
  })
end

--- Process coverage results
function M._process_coverage_results()
  -- Look for coverage files
  local coverage_files = vim.fn.glob("**/TestResults/**/coverage.cobertura.xml", false, true)
  
  if #coverage_files > 0 then
    logger.info("Coverage report generated: " .. coverage_files[1])
  else
    logger.warn("No coverage files found")
  end
end

--- Shutdown test framework
function M.shutdown()
  if M._initialized then
    -- Cancel running tests
    for scope, _ in pairs(M._running_tests) do
      logger.debug("Cancelling running tests: " .. scope)
    end
    
    M._running_tests = {}
    M._discovered_tests = {}
    M._test_results = {}
    M._initialized = false
    
    logger.info("Test framework shutdown")
  end
end

return M
