-- Basic usage example for dotnet-plugin.nvim
-- This demonstrates the core functionality implemented in Month 1

-- Add the plugin to the runtime path
vim.opt.rtp:prepend('.')

-- Initialize the plugin
require('dotnet-plugin').setup({
  dotnet_path = "dotnet",
  max_parallel_builds = 6,

  -- High-performance JSON cache (Phase 1.2 - no external dependencies)
  cache = {
    enabled = true,
    max_age_days = 30,
    cleanup_on_startup = true
  },

  -- Real-time file watching (Phase 1.2)
  watchers = {
    enabled = true,
    auto_watch_solutions = true,
    auto_watch_projects = true,
    auto_reload_on_change = false
  },

  logging = {
    level = "debug",
    file_enabled = true,
    buffer_enabled = true
  }
})

-- Get required modules
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local process = require('dotnet-plugin.core.process')
local logger = require('dotnet-plugin.core.logger')
local solution_parser = require('dotnet-plugin.solution.parser')
local project_parser = require('dotnet-plugin.project.parser')
local dependencies = require('dotnet-plugin.solution.dependencies')

-- Example 1: Configuration Management
print("=== Configuration Example ===")
print("Dotnet path:", config.get_value("dotnet_path"))
print("Max parallel builds:", config.get_value("max_parallel_builds"))
print("Log level:", config.get_value("logging.level"))

-- Update configuration
config.set_value("max_parallel_builds", 8)
print("Updated max parallel builds:", config.get_value("max_parallel_builds"))

-- Example 2: Event System
print("\n=== Event System Example ===")

-- Subscribe to solution events
events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
  print("Solution loaded event received:", data.path)
end)

events.subscribe(events.EVENTS.BUILD_STARTED, function(data)
  print("Build started for project:", data.project or "unknown")
end)

-- Emit some events
events.emit(events.EVENTS.SOLUTION_LOADED, { path = "/example/solution.sln" })
events.emit(events.EVENTS.BUILD_STARTED, { project = "ExampleProject" })

-- Process the event queue
events.process_queue()

-- Example 3: Process Management
print("\n=== Process Management Example ===")

-- Execute a simple dotnet command
local result = process.dotnet({ "--version" })
if result.exit_code == 0 then
  print("Dotnet version:", table.concat(result.stdout, "\n"))
else
  print("Failed to get dotnet version:", table.concat(result.stderr, "\n"))
end

-- Example 4: Solution Parsing
print("\n=== Solution Parsing Example ===")

-- Create a sample solution file for demonstration
local sample_solution_content = [[
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "WebApp", "src\WebApp\WebApp.csproj", "{12345678-1234-1234-1234-123456789012}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "ClassLibrary", "src\ClassLibrary\ClassLibrary.csproj", "{87654321-4321-4321-4321-210987654321}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
EndGlobal
]]

-- Write sample solution to temp file
local temp_sln = vim.fn.tempname() .. ".sln"
vim.fn.writefile(vim.split(sample_solution_content, "\n"), temp_sln)

-- Parse the solution
local solution = solution_parser.parse_solution(temp_sln)
if solution then
  print("Solution name:", solution.name)
  print("Format version:", solution.format_version)
  print("Number of projects:", #solution.projects)
  
  for i, project in ipairs(solution.projects) do
    print(string.format("  Project %d: %s (%s)", i, project.name, project.type))
  end
else
  print("Failed to parse solution")
end

-- Example 5: Project Parsing
print("\n=== Project Parsing Example ===")

-- Create a sample project file
local sample_project_content = [[
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <AssemblyName>WebApp</AssemblyName>
  </PropertyGroup>
  
  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.App" Version="6.0.0" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
  </ItemGroup>
  
  <ItemGroup>
    <ProjectReference Include="..\ClassLibrary\ClassLibrary.csproj" />
  </ItemGroup>
</Project>
]]

-- Write sample project to temp file
local temp_proj = vim.fn.tempname() .. ".csproj"
vim.fn.writefile(vim.split(sample_project_content, "\n"), temp_proj)

-- Parse the project
local project = project_parser.parse_project(temp_proj)
if project then
  print("Project name:", project.name)
  print("Target framework:", project.framework)
  print("Output type:", project.output_type)
  print("Assembly name:", project.assembly_name)
  print("Package references:", #project.package_references)
  
  for i, pkg in ipairs(project.package_references) do
    print(string.format("  Package %d: %s v%s", i, pkg.name, pkg.version))
  end
  
  print("Project references:", #project.project_references)
  for i, ref in ipairs(project.project_references) do
    print(string.format("  Reference %d: %s", i, ref.path))
  end
else
  print("Failed to parse project")
end

-- Example 6: Dependency Tracking
print("\n=== Dependency Tracking Example ===")

-- Create a dependency graph
local graph = dependencies.create_graph()

-- Add projects to the graph (using our parsed project)
if project then
  dependencies.add_project(graph, project)
  dependencies.add_project_dependencies(graph, project)
  
  local project_id = dependencies.get_project_id(project.path)
  print("Project ID:", project_id)
  
  local deps = dependencies.get_dependencies(graph, project_id)
  print("Direct dependencies:", #deps)
  
  local package_stats = dependencies.get_package_stats(graph)
  print("Package statistics:")
  for package_key, stats in pairs(package_stats) do
    print(string.format("  %s: used by %d projects", stats.name, stats.usage_count))
  end
end

-- Example 7: Logging
print("\n=== Logging Example ===")

logger.info("This is an info message")
logger.warn("This is a warning message")
logger.debug("This is a debug message (visible because log level is debug)")
logger.error("This is an error message")

-- Log with context
logger.info("Processing project", {
  name = "ExampleProject",
  framework = "net6.0",
  dependencies = 5
})

-- Example 8: File System Utilities
print("\n=== File System Utilities Example ===")

local fs = require('dotnet-plugin.utils.fs')

-- Demonstrate path operations
local test_path = "/example/path/to/project.csproj"
print("File name:", fs.get_name(test_path))
print("Extension:", fs.get_extension(test_path))
print("Directory:", fs.get_directory(test_path))
print("Is absolute:", fs.is_absolute(test_path))

-- Join paths
local joined = fs.join("/base", "path", "file.txt")
print("Joined path:", joined)

-- Clean up temp files
vim.fn.delete(temp_sln)
vim.fn.delete(temp_proj)

print("\n=== Example completed successfully! ===")
print("Check the log file for detailed output:", config.get_value("logging.file_path"))
