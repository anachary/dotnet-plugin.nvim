# Developer Guide: dotnet-plugin.nvim

## Overview

This guide explains how to use, extend, and contribute to dotnet-plugin.nvim. It covers the APIs, extension points, and development workflows established in Month 1.

## 🚀 Getting Started

### Installation

```lua
-- Using lazy.nvim
{
  "your-username/dotnet-plugin.nvim",
  config = function()
    require("dotnet-plugin").setup({
      -- Your configuration here
    })
  end
}

-- Using packer.nvim
use {
  "your-username/dotnet-plugin.nvim",
  config = function()
    require("dotnet-plugin").setup()
  end
}
```

### Basic Configuration

```lua
require("dotnet-plugin").setup({
  -- .NET CLI settings
  dotnet_path = "dotnet",
  msbuild_path = "msbuild",
  
  -- Performance settings
  max_parallel_builds = 4,
  
  -- Logging configuration
  logging = {
    level = "info",           -- debug, info, warn, error
    file_enabled = true,      -- Log to file
    buffer_enabled = false,   -- Log to buffer
  },
  
  -- Solution management
  solution = {
    auto_detect = true,       -- Auto-detect solutions
    search_depth = 3,         -- Directory search depth
    cache_enabled = true,     -- Enable project caching
    watch_files = true,       -- Watch for file changes
  },
  
  -- Project settings
  project = {
    auto_restore = true,      -- Auto-restore packages
    build_on_save = false,    -- Build on file save
    default_configuration = "Debug",
    default_platform = "AnyCPU"
  }
})
```

## 📚 Core APIs

### Configuration API

```lua
local config = require('dotnet-plugin.core.config')

-- Get configuration values
local dotnet_path = config.get_value("dotnet_path")
local log_level = config.get_value("logging.level")

-- Update configuration at runtime
config.set_value("max_parallel_builds", 8)
config.set_value("logging.level", "debug")

-- Get entire configuration
local cfg = config.get()
```

### Event System API

```lua
local events = require('dotnet-plugin.core.events')

-- Available events
events.EVENTS = {
  -- Solution events
  SOLUTION_LOADING = "dotnet_plugin_solution_loading",
  SOLUTION_LOADED = "dotnet_plugin_solution_loaded",
  SOLUTION_UNLOADED = "dotnet_plugin_solution_unloaded",
  SOLUTION_ERROR = "dotnet_plugin_solution_error",
  
  -- Project events
  PROJECT_LOADING = "dotnet_plugin_project_loading",
  PROJECT_LOADED = "dotnet_plugin_project_loaded",
  PROJECT_CHANGED = "dotnet_plugin_project_changed",
  PROJECT_ERROR = "dotnet_plugin_project_error",
  
  -- Build events
  BUILD_STARTED = "dotnet_plugin_build_started",
  BUILD_PROGRESS = "dotnet_plugin_build_progress",
  BUILD_COMPLETED = "dotnet_plugin_build_completed",
  BUILD_FAILED = "dotnet_plugin_build_failed",
  
  -- File events
  FILE_CREATED = "dotnet_plugin_file_created",
  FILE_MODIFIED = "dotnet_plugin_file_modified",
  FILE_DELETED = "dotnet_plugin_file_deleted",
  
  -- Buffer events
  BUFFER_OPENED = "dotnet_plugin_buffer_opened",
  BUFFER_CLOSED = "dotnet_plugin_buffer_closed",
  BUFFER_SAVED = "dotnet_plugin_buffer_saved",
  
  -- Process events
  PROCESS_STARTED = "dotnet_plugin_process_started",
  PROCESS_COMPLETED = "dotnet_plugin_process_completed",
  PROCESS_FAILED = "dotnet_plugin_process_failed"
}

-- Subscribe to events
local listener_id = events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
  print("Solution loaded:", data.path)
  print("Projects found:", #data.projects)
end, {
  priority = 10,  -- Higher priority = called first
  once = false    -- Set to true for one-time listeners
})

-- Emit custom events
events.emit(events.EVENTS.BUILD_STARTED, {
  project = "MyProject",
  configuration = "Debug"
})

-- Unsubscribe from events
events.unsubscribe(events.EVENTS.SOLUTION_LOADED, listener_id)
```

### Process Management API

```lua
local process = require('dotnet-plugin.core.process')

-- Execute .NET commands synchronously
local result = process.dotnet({ "build", "MyProject.csproj" })
if result.exit_code == 0 then
  print("Build successful!")
  for _, line in ipairs(result.stdout) do
    print("Output:", line)
  end
else
  print("Build failed!")
  for _, line in ipairs(result.stderr) do
    print("Error:", line)
  end
end

-- Execute commands asynchronously
local process_id = process.start("dotnet", {
  args = { "run", "--project", "MyProject.csproj" },
  cwd = "/path/to/project",
  timeout = 30000, -- 30 seconds
  
  on_stdout = function(line)
    print("Output:", line)
  end,
  
  on_stderr = function(line)
    print("Error:", line)
  end,
  
  on_exit = function(result)
    print("Process completed with exit code:", result.exit_code)
    print("Duration:", result.duration, "ms")
  end
})

-- Check if process is running
if process.is_running(process_id) then
  print("Process is still running")
end

-- Kill a process
process.kill(process_id)

-- Execute MSBuild commands
local build_result = process.msbuild({
  "MyProject.csproj",
  "/p:Configuration=Release",
  "/p:Platform=AnyCPU"
})
```

### Logging API

```lua
local logger = require('dotnet-plugin.core.logger')

-- Basic logging
logger.debug("Debug message")
logger.info("Information message")
logger.warn("Warning message")
logger.error("Error message")

-- Structured logging with context
logger.info("Processing project", {
  name = "MyProject",
  framework = "net6.0",
  dependencies = 5,
  build_time = 1234
})

-- Runtime log level changes
logger.set_level("debug")  -- or logger.LEVELS.DEBUG

-- Open log buffer in a window
logger.open_log()

-- Clear log file and buffer
logger.clear()
```

### Solution Parser API

```lua
local solution_parser = require('dotnet-plugin.solution.parser')

-- Parse a solution file
local solution = solution_parser.parse_solution("/path/to/solution.sln")
if solution then
  print("Solution:", solution.name)
  print("Format version:", solution.format_version)
  print("VS version:", solution.visual_studio_version)
  
  for _, project in ipairs(solution.projects) do
    print("Project:", project.name, "Type:", project.type)
    print("Path:", project.path)
    print("Dependencies:", #project.dependencies)
  end
end

-- Find solutions in a directory
local solutions = solution_parser.find_solutions("/workspace", 3)
for _, sln_path in ipairs(solutions) do
  print("Found solution:", sln_path)
end

-- Validate solution structure
local valid, errors = solution_parser.validate_solution(solution)
if not valid then
  for _, error in ipairs(errors) do
    print("Validation error:", error)
  end
end
```

### Project Parser API

```lua
local project_parser = require('dotnet-plugin.project.parser')

-- Parse a project file
local project = project_parser.parse_project("/path/to/project.csproj")
if project then
  print("Project:", project.name)
  print("Framework:", project.framework)
  print("Output type:", project.output_type)
  print("Assembly name:", project.assembly_name)
  
  -- Package references
  print("Package references:")
  for _, pkg in ipairs(project.package_references) do
    print("  ", pkg.name, "v" .. pkg.version)
  end
  
  -- Project references
  print("Project references:")
  for _, ref in ipairs(project.project_references) do
    print("  ", ref.name, "->", ref.path)
  end
end

-- Get project dependencies
local deps = project_parser.get_dependencies(project)
print("Package dependencies:", #deps.packages)
print("Project dependencies:", #deps.projects)

-- Check framework support
if project_parser.supports_framework(project, "net6.0") then
  print("Project supports .NET 6.0")
end

-- Get output path
local output_path = project_parser.get_output_path(project, "Release", "net6.0")
print("Output path:", output_path)
```

### Dependency Tracking API

```lua
local dependencies = require('dotnet-plugin.solution.dependencies')

-- Create dependency graph
local graph = dependencies.create_graph()

-- Add projects to graph
for _, project in ipairs(solution.projects) do
  local parsed_project = project_parser.parse_project(project.path)
  if parsed_project then
    dependencies.add_project(graph, parsed_project)
    dependencies.add_project_dependencies(graph, parsed_project)
  end
end

-- Get build order
local build_order = dependencies.get_build_order(graph)
if build_order then
  print("Build order:")
  for i, project_id in ipairs(build_order) do
    print(i, project_id)
  end
else
  print("Circular dependencies detected!")
end

-- Check for circular dependencies
local has_cycles, cycles = dependencies.check_circular_dependencies(graph)
if has_cycles then
  print("Circular dependencies found:")
  for _, cycle in ipairs(cycles) do
    print("Cycle:", table.concat(cycle, " -> "))
  end
end

-- Get parallel build groups
local parallel_groups = dependencies.get_parallel_build_groups(graph)
print("Parallel build groups:")
for i, group in ipairs(parallel_groups) do
  print("Group", i, ":", table.concat(group, ", "))
end

-- Get package statistics
local package_stats = dependencies.get_package_stats(graph)
for package_key, stats in pairs(package_stats) do
  print(stats.name, "v" .. stats.version, "used by", stats.usage_count, "projects")
end
```

### File System Utilities API

```lua
local fs = require('dotnet-plugin.utils.fs')

-- Path operations
local project_dir = fs.get_directory("/path/to/project.csproj")
local project_name = fs.get_name("/path/to/project.csproj")
local extension = fs.get_extension("/path/to/project.csproj")

-- Join paths (cross-platform)
local bin_path = fs.join(project_dir, "bin", "Debug", "net6.0")

-- Check file/directory existence
if fs.exists("/path/to/file") then
  if fs.is_file("/path/to/file") then
    print("It's a file")
  elseif fs.is_directory("/path/to/file") then
    print("It's a directory")
  end
end

-- Read and write files
local lines = fs.read_file("/path/to/file.txt")
if lines then
  -- Modify lines
  table.insert(lines, "New line")
  fs.write_file("/path/to/output.txt", lines)
end

-- Find files and directories
local csproj_files = fs.find_files("/workspace", "*.csproj", true)
local bin_dirs = fs.find_directories("/workspace", "bin", true)

-- File watching
local handle = fs.watch("/path/to/watch", function(filename, events)
  print("File changed:", filename, "Events:", vim.inspect(events))
end)

-- Stop watching
fs.unwatch(handle)

-- Path utilities
local abs_path = fs.absolute("relative/path", "/base/directory")
local rel_path = fs.relative("/absolute/path", "/base/directory")
local is_abs = fs.is_absolute("/absolute/path")
```

## 🔌 Extension Points

### Creating Custom Event Handlers

```lua
-- Custom solution analyzer
local events = require('dotnet-plugin.core.events')
local logger = require('dotnet-plugin.core.logger')

events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
  logger.info("Analyzing solution", { path = data.path })
  
  -- Custom analysis logic
  local large_projects = {}
  for _, project in ipairs(data.projects) do
    if project.type == "csharp" then
      -- Analyze project size, complexity, etc.
      table.insert(large_projects, project.name)
    end
  end
  
  if #large_projects > 0 then
    logger.warn("Large projects detected", { projects = large_projects })
  end
end, { priority = 5 })
```

### Custom Build Workflows

```lua
-- Custom build pipeline
local process = require('dotnet-plugin.core.process')
local events = require('dotnet-plugin.core.events')

local function custom_build_pipeline(solution_path)
  -- Step 1: Clean
  events.emit(events.EVENTS.BUILD_STARTED, { step = "clean" })
  local clean_result = process.dotnet({ "clean", solution_path })
  
  if clean_result.exit_code ~= 0 then
    events.emit(events.EVENTS.BUILD_FAILED, { step = "clean", error = clean_result.stderr })
    return false
  end
  
  -- Step 2: Restore
  events.emit(events.EVENTS.BUILD_PROGRESS, { step = "restore" })
  local restore_result = process.dotnet({ "restore", solution_path })
  
  if restore_result.exit_code ~= 0 then
    events.emit(events.EVENTS.BUILD_FAILED, { step = "restore", error = restore_result.stderr })
    return false
  end
  
  -- Step 3: Build
  events.emit(events.EVENTS.BUILD_PROGRESS, { step = "build" })
  local build_result = process.dotnet({ "build", solution_path, "--no-restore" })
  
  if build_result.exit_code == 0 then
    events.emit(events.EVENTS.BUILD_COMPLETED, { success = true })
    return true
  else
    events.emit(events.EVENTS.BUILD_FAILED, { step = "build", error = build_result.stderr })
    return false
  end
end
```

### Custom Configuration Schemas

```lua
-- Extend configuration for custom features
local config = require('dotnet-plugin.core.config')

-- Add custom settings at runtime
config.set_value("custom.feature_enabled", true)
config.set_value("custom.api_endpoint", "https://api.example.com")
config.set_value("custom.timeout", 5000)

-- Use custom settings
local function my_custom_feature()
  if config.get_value("custom.feature_enabled") then
    local endpoint = config.get_value("custom.api_endpoint")
    local timeout = config.get_value("custom.timeout")
    -- Custom feature implementation
  end
end
```

## 🧪 Testing and Development

### Running Tests

```bash
# Run all tests
nvim --headless -c "luafile tests/run_tests.lua"

# Run specific test file
nvim --headless -c "luafile tests/core/config_spec.lua"
```

### Writing Tests

```lua
-- tests/my_feature_spec.lua
local my_feature = require('my-plugin.my_feature')

describe("My Feature", function()
  before_each(function()
    -- Setup before each test
  end)
  
  it("should do something", function()
    local result = my_feature.do_something()
    assert.equals("expected", result)
  end)
  
  it("should handle errors", function()
    assert.has_error(function()
      my_feature.invalid_operation()
    end)
  end)
end)
```

### Debugging

```lua
-- Enable debug logging
local logger = require('dotnet-plugin.core.logger')
logger.set_level("debug")

-- Open log buffer to see real-time logs
logger.open_log()

-- Add debug statements to your code
logger.debug("Custom feature called", { param1 = value1, param2 = value2 })
```

## 📖 Best Practices

### Event Handling

1. **Use appropriate priorities**: Higher priority for critical handlers
2. **Handle errors gracefully**: Don't let one handler break others
3. **Unsubscribe when done**: Prevent memory leaks
4. **Use structured data**: Pass meaningful event data

### Process Management

1. **Always handle timeouts**: Set reasonable timeout values
2. **Stream large outputs**: Use callbacks for real-time processing
3. **Check exit codes**: Handle both success and failure cases
4. **Clean up processes**: Kill processes when no longer needed

### Configuration

1. **Validate inputs**: Check configuration values before use
2. **Provide defaults**: Always have sensible fallback values
3. **Document settings**: Explain what each setting does
4. **Use nested structure**: Group related settings together

### Performance

1. **Use async operations**: Don't block the UI thread
2. **Cache expensive operations**: Store parsed data when possible
3. **Lazy load data**: Only parse what's needed
4. **Monitor memory usage**: Clean up unused resources

## 🚀 Next Steps

With the Month 1 foundation in place, you can:

1. **Build custom workflows** using the event system
2. **Integrate with external tools** using the process manager
3. **Create custom analyzers** using the solution/project parsers
4. **Extend the configuration** for your specific needs

The architecture is designed to be extensible, so you can build upon these foundations to create powerful .NET development workflows tailored to your needs.
