-- LSP usage example for dotnet-plugin.nvim
-- This demonstrates the LSP functionality implemented in Phase 1.3

-- Add the plugin to the runtime path
vim.opt.rtp:prepend('.')

-- Initialize the plugin with LSP enabled
require('dotnet-plugin').setup({
  dotnet_path = "dotnet",
  max_parallel_builds = 6,

  -- High-performance JSON cache (Phase 1.2)
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

  -- LSP integration (Phase 1.3) - Roslyn Language Server only
  lsp = {
    enabled = true,
    server = "roslyn",  -- Enterprise-optimized Roslyn only
    auto_start = true,
    auto_attach = true,
    workspace_folders = true,
    diagnostics = {
      enable_background_analysis = true,
      scope = "fullSolution"
    },
    completion = {
      enable_unimported_namespaces = true,
      enable_regex_completions = true
    },
    performance = {
      max_project_count = 1000,  -- Enterprise scale
      enable_server_gc = true,
      use_server_gc = true
    }
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
local logger = require('dotnet-plugin.core.logger')
local lsp = require('dotnet-plugin.lsp')

-- Example 1: LSP Status Check
print("=== LSP Status Example ===")
local lsp_status = require('dotnet-plugin').get_lsp_status()
print("LSP Initialized:", lsp_status.initialized)
print("Active Clients:", lsp_status.active_clients)

-- Example 2: Workspace Information
print("\n=== Workspace Information ===")
local workspace_info = require('dotnet-plugin').get_lsp_workspace_info()
print("Workspace Folders:", vim.inspect(workspace_info.folders))

-- Example 3: Subscribe to LSP Events
print("\n=== LSP Event Subscription ===")
events.subscribe(events.EVENTS.LSP_ATTACHED, function(data)
  print("LSP attached to buffer:", data.buffer)
  print("File:", data.file)
  print("Client:", data.client.name)
end)

events.subscribe(events.EVENTS.LSP_DETACHED, function(data)
  print("LSP detached from buffer")
  print("Exit code:", data.exit_code)
end)

-- Example 4: Custom .NET Commands
print("\n=== Custom .NET Commands Available ===")
print("- :DotnetAddUsing <namespace>     - Add using statement")
print("- :DotnetOrganizeUsings           - Organize using statements")
print("- :DotnetGoToProject              - Open project file")
print("- :DotnetShowDependencies         - Show project dependencies")
print("- :DotnetFindSymbol <symbol>      - Find symbol in solution")
print("- :DotnetSymbolSearch <query>     - Search symbols")
print("- :DotnetGoToSymbol               - Interactive symbol navigation")

-- Example 5: Enhanced Navigation
print("\n=== Enhanced Navigation Features ===")
print("Enhanced LSP features:")
print("- Cross-project go-to-definition")
print("- Solution-wide find references")
print("- Project-aware code completion")
print("- Enhanced hover with project context")
print("- Workspace symbol search")

-- Example 6: Performance Monitoring
print("\n=== Performance Monitoring ===")
local function monitor_lsp_performance()
  local start_time = vim.loop.hrtime()
  
  -- Simulate LSP operation
  vim.defer_fn(function()
    local end_time = vim.loop.hrtime()
    local duration_ms = (end_time - start_time) / 1000000
    print(string.format("LSP operation completed in %.2f ms", duration_ms))
  end, 100)
end

monitor_lsp_performance()

-- Example 7: Solution Context Integration
print("\n=== Solution Context Integration ===")
events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
  print("Solution loaded for LSP:", data.name)
  print("Projects:", #(data.projects or {}))
  
  -- LSP will automatically configure workspace
  local workspace_info = require('dotnet-plugin').get_lsp_workspace_info()
  print("Workspace folders after solution load:", #workspace_info.folders)
end)

-- Example 8: Code Modification Events
events.subscribe(events.EVENTS.CODE_MODIFIED, function(data)
  print("Code modified:", data.type)
  if data.namespace then
    print("Namespace:", data.namespace)
  end
  print("Buffer:", data.buffer)
end)

-- Example 9: Testing LSP with a Sample File
print("\n=== Testing LSP Integration ===")
print("To test LSP integration:")
print("1. Open a .cs file in a .NET project")
print("2. Check LSP status: :lua print(vim.inspect(require('dotnet-plugin').get_lsp_status()))")
print("3. Test completion: Ctrl+X Ctrl+O")
print("4. Test go-to-definition: gd")
print("5. Test find references: gr")
print("6. Test hover: K")

-- Example 10: Enterprise Features
print("\n=== Enterprise Features ===")
print("Roslyn Language Server optimizations:")
print("- Memory efficient: Server GC enabled")
print("- Large solution support: Up to 1000 projects")
print("- Background analysis: Full solution scope")
print("- Cross-project navigation: Enabled")
print("- Unimported namespace completion: Enabled")

print("\n=== LSP Integration Ready! ===")
print("Phase 1.3 LSP features are now available.")
print("Use the commands above to test the functionality.")
