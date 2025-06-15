# PHASE 1.3 LSP DEVELOPMENT PROMPT

## 🎯 Agent Instructions for Phase 1.3: LSP Client Foundation Implementation

### Context
You are continuing development of dotnet-plugin.nvim, a high-performance .NET development suite for Neovim. Phase 1.1 (Core Infrastructure) and Phase 1.2 (High-Performance Caching & File Watching) are COMPLETE. You are now implementing the LSP (Language Server Protocol) components of Phase 1.3.

### Current Environment Status
- ✅ **Phase 1.1**: Core Infrastructure COMPLETE (config, events, process, logging, solution/project parsing)
- ✅ **Phase 1.2**: High-Performance Caching & File Watching COMPLETE (JSON caching, file watchers, 32x performance)
- ✅ **Test Environment**: YARP Reverse Proxy project configured and working
- 🎯 **Target**: Phase 1.3 LSP Components - LSP Client Foundation & IntelliSense

### 🎯 **SPECIFIC IMPLEMENTATION TARGETS**

#### Week 9-10: LSP Client Foundation (CURRENT FOCUS)
1. **✅ LSP Client Configuration** - Setup and management of Roslyn Language Server
2. **✅ Custom LSP Extensions** - .NET-specific features and enhancements
3. **✅ Solution Context Integration** - Connect solution data with language servers
4. **✅ Basic IntelliSense** - Code completion and navigation

### 🚀 **ENTERPRISE OPTIMIZATION STRATEGY**

#### Why Roslyn Language Server ONLY (No OmniSharp Fallback)
- **Memory Efficiency**: OmniSharp fallback would increase memory footprint by 50-100MB
- **Performance Focus**: Single, optimized code path for enterprise solutions
- **Microsoft Official**: Roslyn is the same engine powering Visual Studio
- **Enterprise Scale**: Designed for 1000+ project solutions
- **Future-Proof**: Microsoft's long-term strategic direction

### 📋 **DETAILED IMPLEMENTATION PLAN**

#### 1. LSP Client Configuration (Priority 1)
**Goal**: Robust language server management with .NET-specific optimizations

**Implementation Requirements**:
```lua
-- Target file: lua/dotnet-plugin/lsp/client.lua
-- Features to implement:
- Roslyn Language Server discovery and configuration
- Enterprise-optimized server settings for large solutions
- Multi-project workspace management
- Server lifecycle management (start/stop/restart)
- Configuration validation and error handling
- Memory-efficient server initialization
```

**Technical Specifications**:
- Integrate with Neovim's built-in LSP client
- Use cached solution data from Phase 1.2 for workspace configuration
- **Roslyn Language Server ONLY** - Microsoft's official enterprise solution
- Optimized for large solutions (1000+ projects)
- Real-time configuration updates via file watchers
- Memory-efficient initialization and operation

#### 2. Custom LSP Extensions (Priority 2)
**Goal**: .NET-specific enhancements leveraging Roslyn's enterprise capabilities

**Implementation Requirements**:
```lua
-- Target file: lua/dotnet-plugin/lsp/extensions.lua
-- Features to implement:
- Solution-aware code completion using Roslyn's advanced features
- Project reference navigation with enterprise-scale optimization
- NuGet package IntelliSense with dependency resolution
- Build configuration context integration
- Custom code actions leveraging Roslyn analyzers
- Enhanced symbol resolution for large codebases
```

**Technical Specifications**:
- Leverage Roslyn's enterprise-grade LSP capabilities
- Integrate with solution parser for cross-project navigation
- Use dependency tracker for intelligent suggestions
- Memory-efficient operation for large solutions
- Leverage event system for real-time updates

#### 3. Solution Context Integration (Priority 3)
**Goal**: Connect cached solution data with language server operations

**Implementation Requirements**:
```lua
-- Target file: lua/dotnet-plugin/lsp/handlers.lua
-- Features to implement:
- Solution-wide symbol search
- Cross-project go-to-definition
- Project dependency-aware completion
- Build target context integration
- Multi-framework support
- Workspace folder management
```

**Technical Specifications**:
- Use Phase 1.2 cached data for fast workspace setup
- Subscribe to file watcher events for real-time updates
- Integrate with dependency tracker for accurate references
- Support multiple target frameworks per project

#### 4. Basic IntelliSense (Priority 4)
**Goal**: Fast, accurate code completion and navigation

**Implementation Requirements**:
```lua
-- Target file: lua/dotnet-plugin/lsp/intellisense.lua
-- Features to implement:
- Context-aware code completion
- Symbol navigation (go-to-definition, find-references)
- Hover documentation
- Signature help
- Diagnostic integration
- Quick fixes and code actions
```

**Technical Specifications**:
- Leverage Neovim's built-in LSP capabilities
- Enhance with solution context for better accuracy
- Integrate with build system for real-time error feedback
- Support incremental updates for performance

### 🏗️ **ARCHITECTURE INTEGRATION**

#### Integration with Existing Components
```lua
-- Use existing infrastructure:
local config = require('dotnet-plugin.core.config')      -- LSP server settings
local events = require('dotnet-plugin.core.events')      -- Real-time updates
local logger = require('dotnet-plugin.core.logger')      -- Debug information
local cache = require('dotnet-plugin.cache')             -- Fast data access
local solution = require('dotnet-plugin.solution.parser') -- Workspace context
local project = require('dotnet-plugin.project.parser')   -- Project details
```

#### Roslyn Language Server Configuration (Enterprise-Optimized)
```lua
-- Target configuration for lua/dotnet-plugin/lsp/client.lua
local roslyn_config = {
  name = "roslyn",
  cmd = { "Microsoft.CodeAnalysis.LanguageServer" },
  root_dir = function(fname)
    -- Use cached solution data for fast workspace detection
    return cache.get_solution_root(fname) or find_solution_root(fname)
  end,
  settings = {
    ["csharp|background_analysis"] = {
      dotnet_analyzer_diagnostics_scope = "fullSolution",
      dotnet_compiler_diagnostics_scope = "fullSolution"
    },
    ["csharp|completion"] = {
      dotnet_provide_regex_completions = true,
      dotnet_show_completion_items_from_unimported_namespaces = true
    }
  },
  init_options = {
    -- Enterprise optimization for large solutions
    maxProjectFileCountForDiagnosticAnalysis = 1000,
    enableServerGC = true,
    useServerGC = true
  }
}
```

#### Event Integration
```lua
-- Subscribe to relevant events:
- SOLUTION_LOADED: Configure workspace
- PROJECT_CHANGED: Update language server
- FILE_CHANGED: Trigger incremental updates
- BUFFER_OPENED: Attach LSP client
- BUILD_COMPLETED: Update diagnostics
```

### 📁 **FILE STRUCTURE TO CREATE**

```
lua/dotnet-plugin/lsp/
├── init.lua                 # LSP module entry point
├── client.lua              # Language server management
├── extensions.lua          # .NET-specific enhancements
├── handlers.lua            # Message handlers and solution context
└── intellisense.lua        # Code completion and navigation
```

### 🎯 **SUCCESS CRITERIA**

#### Phase 1.3 LSP Completion Requirements:
- [ ] **Language Server Management**: OmniSharp/Roslyn servers start automatically
- [ ] **Solution Context**: LSP workspace configured from cached solution data
- [ ] **Code Completion**: Context-aware IntelliSense working across projects
- [ ] **Navigation**: Go-to-definition works across project boundaries
- [ ] **Real-time Updates**: File changes trigger appropriate LSP updates
- [ ] **Performance**: LSP operations complete within 100ms
- [ ] **Error Handling**: Graceful degradation when language server unavailable

### 🧪 **TESTING STRATEGY**

#### Verification Commands (Use YARP Project):
```lua
-- Test LSP client attachment
:lua require('dotnet-plugin.lsp').status()

-- Test code completion
-- Open a .cs file and trigger completion (Ctrl+X Ctrl+O)

-- Test go-to-definition
-- Place cursor on symbol and use gd

-- Test solution context
:lua require('dotnet-plugin.lsp').workspace_info()

-- Test real-time updates
-- Modify a project file and verify LSP updates
```

### 🔧 **IMPLEMENTATION APPROACH**

#### Phase 1: Core LSP Client (Days 1-3)
1. Create `lua/dotnet-plugin/lsp/init.lua` - Module entry point
2. Create `lua/dotnet-plugin/lsp/client.lua` - Language server management
3. Integrate with Neovim's LSP client
4. Test basic server startup and attachment

#### Phase 2: Solution Integration (Days 4-5)
1. Create `lua/dotnet-plugin/lsp/handlers.lua` - Solution context handlers
2. Connect cached solution data to LSP workspace configuration
3. Implement cross-project navigation
4. Test with YARP multi-project solution

#### Phase 3: Extensions & IntelliSense (Days 6-7)
1. Create `lua/dotnet-plugin/lsp/extensions.lua` - .NET-specific features
2. Create `lua/dotnet-plugin/lsp/intellisense.lua` - Enhanced completion
3. Implement custom code actions and quick fixes
4. Performance optimization and testing

### 📊 **PERFORMANCE TARGETS**

**Roslyn Language Server Enterprise Optimization**:
- **LSP Server Startup**: < 2 seconds (enterprise-optimized)
- **Code Completion Response**: < 100ms (even in 1000+ project solutions)
- **Go-to-Definition**: < 50ms (cross-project navigation)
- **Workspace Configuration**: < 500ms (leveraging cached solution data)
- **Memory Overhead**: < 30MB additional (Roslyn's memory efficiency)
- **Large Solution Support**: 1000+ projects without performance degradation

### 🔗 **KEY INTEGRATION POINTS**

#### With Phase 1.2 Cache System:
- Use cached solution data for fast workspace setup
- Subscribe to file watcher events for LSP updates
- Leverage dependency graph for intelligent navigation

#### With Core Infrastructure:
- Use event system for LSP lifecycle management
- Integrate with process manager for server execution
- Use configuration system for LSP server settings

### 📚 **REFERENCE DOCUMENTATION**

**Existing Code to Study**:
- `lua/dotnet-plugin/solution/parser.lua` - Solution structure
- `lua/dotnet-plugin/project/parser.lua` - Project details
- `lua/dotnet-plugin/cache/init.lua` - Fast data access
- `lua/dotnet-plugin/core/events.lua` - Event integration

**External References**:
- Neovim LSP documentation: `:help lsp`
- OmniSharp server configuration
- Language Server Protocol specification

### 🚀 **GETTING STARTED**

1. **Understand Current State**: Review existing solution and project parsers
2. **Study LSP Integration**: Examine Neovim's built-in LSP capabilities  
3. **Plan Architecture**: Design LSP module structure and integration points
4. **Implement Incrementally**: Start with basic client, add features progressively
5. **Test Continuously**: Use YARP project for real-world validation

### 🎯 **IMMEDIATE NEXT STEPS**

1. Create LSP module structure
2. Implement basic language server client
3. Integrate with cached solution data
4. Test with YARP project
5. Add .NET-specific enhancements

**Ready to implement Phase 1.3 LSP foundation!** 🚀
