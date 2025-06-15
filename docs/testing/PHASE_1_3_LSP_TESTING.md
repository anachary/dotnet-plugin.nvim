# Phase 1.3 LSP Testing Guide

## 🎯 Overview

This guide provides comprehensive testing procedures for the Phase 1.3 LSP (Language Server Protocol) implementation in dotnet-plugin.nvim. The LSP integration provides enterprise-grade IntelliSense capabilities using Microsoft's Roslyn Language Server.

## 🚀 **Key Features Implemented**

### ✅ **LSP Client Configuration**
- Roslyn Language Server integration (enterprise-optimized)
- Automatic workspace detection using cached solution data
- Memory-efficient configuration (no OmniSharp fallback)
- Enterprise-scale support (1000+ projects)

### ✅ **Custom LSP Extensions**
- .NET-specific commands and code actions
- Solution-aware features
- Project dependency management
- Enhanced symbol navigation

### ✅ **Solution Context Integration**
- Cross-project go-to-definition
- Solution-wide find references
- Project-aware code completion
- Workspace folder management

### ✅ **Enhanced IntelliSense**
- Context-aware code completion
- Enhanced hover with project information
- Symbol search across solution
- Interactive navigation features

## 🧪 **Testing Prerequisites**

### Required Setup
1. **Neovim 0.8+** with LSP support
2. **.NET SDK 6.0+** installed
3. **Roslyn Language Server** available
4. **Test project** (YARP Reverse Proxy recommended)
5. **dotnet-plugin.nvim** with Phase 1.3 LSP modules

### Configuration
```lua
require('dotnet-plugin').setup({
  -- Enable LSP with enterprise optimizations
  lsp = {
    enabled = true,
    server = "roslyn",  -- Roslyn only, no OmniSharp fallback
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
      max_project_count = 1000,
      enable_server_gc = true,
      use_server_gc = true
    }
  },
  
  -- Enable caching for fast workspace detection
  cache = {
    enabled = true,
    max_age_days = 30
  },
  
  -- Enable file watchers for real-time updates
  watchers = {
    enabled = true,
    auto_watch_solutions = true,
    auto_watch_projects = true
  },
  
  logging = {
    level = "debug",  -- For testing
    file_enabled = true
  }
})
```

## 🔍 **Testing Procedures**

### Test 1: LSP Initialization
**Objective**: Verify LSP system initializes correctly

```lua
-- Check LSP status
:lua print(vim.inspect(require('dotnet-plugin').get_lsp_status()))

-- Expected output:
-- {
--   initialized = true,
--   active_clients = 0,  -- Will increase when files are opened
--   client_status = { initialized = true, active_clients = 0, workspace_folders = 0 },
--   handlers_status = { initialized = true, enhanced_handlers = {...} },
--   extensions_status = { initialized = true, custom_commands = 5 },
--   intellisense_status = { initialized = true, cached_symbols = 0, cached_completions = 0 }
-- }
```

**Success Criteria**:
- ✅ `initialized = true` for all components
- ✅ No error messages in logs
- ✅ Custom commands available

### Test 2: Workspace Detection
**Objective**: Verify automatic workspace detection using cached solution data

```bash
# Open a .cs file in a .NET project
nvim YarpReverseProxy/src/ReverseProxy/Program.cs
```

```lua
-- Check workspace information
:lua print(vim.inspect(require('dotnet-plugin').get_lsp_workspace_info()))

-- Expected output:
-- {
--   folders = { "/path/to/YarpReverseProxy" },
--   active_clients = { buffer_numbers... }
-- }
```

**Success Criteria**:
- ✅ Solution root directory detected automatically
- ✅ Workspace folder configured correctly
- ✅ LSP client attached to buffer

### Test 3: Code Completion
**Objective**: Test enhanced IntelliSense with solution context

```csharp
// In a .cs file, type:
using System.
// Press Ctrl+X Ctrl+O for completion

// Or type:
Console.
// Should show completion items
```

**Success Criteria**:
- ✅ Completion items appear within 100ms
- ✅ Items include project-specific context
- ✅ Unimported namespaces suggested
- ✅ Documentation includes project information

### Test 4: Go-to-Definition (Cross-Project)
**Objective**: Test cross-project navigation

```csharp
// Place cursor on a symbol from another project
// Press 'gd' for go-to-definition
```

**Success Criteria**:
- ✅ Navigation works across project boundaries
- ✅ Response time < 50ms
- ✅ Correct file and location opened
- ✅ Project context preserved

### Test 5: Find References (Solution-Wide)
**Objective**: Test solution-wide reference search

```csharp
// Place cursor on a symbol
// Press 'gr' for find references
```

**Success Criteria**:
- ✅ References found across entire solution
- ✅ Results grouped by project
- ✅ Quickfix list populated correctly
- ✅ Project information displayed

### Test 6: Enhanced Hover
**Objective**: Test hover with project context

```csharp
// Hover over a symbol (press 'K')
```

**Success Criteria**:
- ✅ Hover information appears
- ✅ Project context included in documentation
- ✅ Framework information displayed
- ✅ Response time < 100ms

### Test 7: Custom .NET Commands
**Objective**: Test .NET-specific extensions

```vim
" Test custom commands
:DotnetAddUsing System.Threading.Tasks
:DotnetOrganizeUsings
:DotnetGoToProject
:DotnetShowDependencies
:DotnetFindSymbol Program
:DotnetSymbolSearch Main
:DotnetGoToSymbol
```

**Success Criteria**:
- ✅ All commands execute without errors
- ✅ Using statements added/organized correctly
- ✅ Project file opens correctly
- ✅ Dependencies displayed in floating window
- ✅ Symbol search works across solution

### Test 8: Real-Time Updates
**Objective**: Test file watcher integration with LSP

```bash
# Modify a project file externally
echo '<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />' >> Project.csproj
```

**Success Criteria**:
- ✅ LSP notified of project changes
- ✅ Workspace configuration updated
- ✅ IntelliSense reflects new dependencies
- ✅ No manual restart required

### Test 9: Performance Testing
**Objective**: Verify performance targets are met

```lua
-- Monitor LSP performance
:lua vim.lsp.set_log_level("debug")

-- Test completion performance
-- Type and trigger completion multiple times
-- Check response times in logs
```

**Performance Targets**:
- ✅ LSP server startup: < 2 seconds
- ✅ Code completion: < 100ms
- ✅ Go-to-definition: < 50ms
- ✅ Workspace configuration: < 500ms
- ✅ Memory overhead: < 30MB

### Test 10: Error Handling
**Objective**: Test graceful error handling

```lua
-- Test with invalid project
:e InvalidProject.cs

-- Test LSP restart
:lua require('dotnet-plugin').restart_lsp()

-- Check error handling
:lua print(vim.inspect(vim.lsp.get_active_clients()))
```

**Success Criteria**:
- ✅ Graceful degradation when LSP unavailable
- ✅ Error messages are informative
- ✅ Plugin continues to function
- ✅ LSP restart works correctly

## 📊 **Performance Benchmarks**

### Expected Performance Metrics
- **Memory Usage**: < 30MB additional (Roslyn efficiency)
- **Startup Time**: < 2 seconds for LSP server
- **Completion Response**: < 100ms (even in 1000+ project solutions)
- **Navigation Speed**: < 50ms for cross-project operations
- **Workspace Setup**: < 500ms using cached solution data

### Monitoring Commands
```lua
-- Check memory usage
:lua print("LSP Memory:", vim.fn.system("ps -o rss= -p " .. vim.fn.getpid()))

-- Check active clients
:lua print(vim.inspect(vim.lsp.get_active_clients()))

-- Check LSP logs
:lua vim.cmd('edit ' .. vim.lsp.get_log_path())
```

## 🐛 **Troubleshooting**

### Common Issues

#### LSP Not Starting
```lua
-- Check configuration
:lua print(vim.inspect(require('dotnet-plugin.core.config').get_value("lsp")))

-- Check Roslyn availability
:!which Microsoft.CodeAnalysis.LanguageServer
```

#### Completion Not Working
```lua
-- Check LSP attachment
:lua print(vim.inspect(vim.lsp.buf_get_clients()))

-- Check capabilities
:lua print(vim.inspect(vim.lsp.get_active_clients()[1].server_capabilities))
```

#### Workspace Issues
```lua
-- Check workspace folders
:lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))

-- Check solution detection
:lua print(vim.inspect(require('dotnet-plugin.cache').get_solution_root(vim.fn.expand('%:p'))))
```

## ✅ **Success Criteria Summary**

Phase 1.3 LSP implementation is successful when:

### Core Functionality
- [x] Roslyn Language Server starts automatically
- [x] LSP attaches to .NET files without manual intervention
- [x] Code completion works with project context
- [x] Cross-project navigation functions correctly
- [x] Solution-wide search operates as expected

### Performance
- [x] All operations meet performance targets
- [x] Memory usage stays within limits
- [x] No blocking operations in UI
- [x] Responsive even with large solutions

### Integration
- [x] Seamless integration with Phase 1.2 cache system
- [x] File watcher events trigger LSP updates
- [x] Event system properly connected
- [x] Configuration system working correctly

### Enterprise Features
- [x] Support for 1000+ project solutions
- [x] Memory-efficient single server approach
- [x] Background analysis for full solution
- [x] Unimported namespace completion

## 🎉 **Phase 1.3 LSP Complete!**

When all tests pass, Phase 1.3 LSP Client Foundation & IntelliSense is complete and ready for production use with enterprise .NET solutions.
