-- dotnet-plugin.nvim - Roslyn Language Server Installer
-- Automatic installation and management of Roslyn Language Server

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local process = require('dotnet-plugin.core.process')
local events = require('dotnet-plugin.core.events')

-- Installation state
local installer_initialized = false
local installation_status = {
  installed = false,
  version = nil,
  path = nil,
  installation_method = nil
}

-- Installation methods and paths
local INSTALLATION_METHODS = {
  DOTNET_TOOL = "dotnet_tool",
  VSCODE_EXTENSION = "vscode_extension", 
  MANUAL_DOWNLOAD = "manual_download",
  SYSTEM_PATH = "system_path"
}

local ROSLYN_PATHS = {
  -- Common installation paths for different methods
  dotnet_tool = {
    windows = "%USERPROFILE%\\.dotnet\\tools\\Microsoft.CodeAnalysis.LanguageServer.exe",
    linux = "$HOME/.dotnet/tools/Microsoft.CodeAnalysis.LanguageServer",
    macos = "$HOME/.dotnet/tools/Microsoft.CodeAnalysis.LanguageServer"
  },
  vscode_extension = {
    windows = "%USERPROFILE%\\.vscode\\extensions\\ms-dotnettools.csharp-*\\roslyn\\Microsoft.CodeAnalysis.LanguageServer.exe",
    linux = "$HOME/.vscode/extensions/ms-dotnettools.csharp-*/roslyn/Microsoft.CodeAnalysis.LanguageServer",
    macos = "$HOME/.vscode/extensions/ms-dotnettools.csharp-*/roslyn/Microsoft.CodeAnalysis.LanguageServer"
  }
}

--- Initialize the Roslyn Language Server installer
--- @return boolean success True if installer was initialized successfully
function M.setup()
  if installer_initialized then
    return true
  end

  logger.info("Initializing Roslyn Language Server installer")

  -- Check current installation status
  M._check_installation_status()

  installer_initialized = true
  logger.info("Roslyn Language Server installer initialized")
  
  return true
end

--- Check if Roslyn Language Server is installed and available
--- @return boolean installed True if Roslyn Language Server is available
function M.is_installed()
  if not installer_initialized then
    M.setup()
  end
  
  return installation_status.installed
end

--- Get the path to the Roslyn Language Server executable
--- @return string|nil path Path to the executable or nil if not found
function M.get_server_path()
  if not M.is_installed() then
    return nil
  end
  
  return installation_status.path
end

--- Get installation status information
--- @return table status Installation status details
function M.get_status()
  return vim.tbl_deep_extend("force", {}, installation_status)
end

--- Check current installation status
function M._check_installation_status()
  logger.debug("Checking Roslyn Language Server installation status")

  -- Reset status
  installation_status = {
    installed = false,
    version = nil,
    path = nil,
    installation_method = nil
  }

  -- Check different installation methods in order of preference
  local methods = {
    { method = INSTALLATION_METHODS.SYSTEM_PATH, checker = M._check_system_path },
    { method = INSTALLATION_METHODS.DOTNET_TOOL, checker = M._check_dotnet_tool },
    { method = INSTALLATION_METHODS.VSCODE_EXTENSION, checker = M._check_vscode_extension }
  }

  for _, method_info in ipairs(methods) do
    local path = method_info.checker()
    if path then
      installation_status.installed = true
      installation_status.path = path
      installation_status.installation_method = method_info.method
      
      -- Try to get version
      installation_status.version = M._get_server_version(path)
      
      logger.info("Found Roslyn Language Server", {
        method = method_info.method,
        path = path,
        version = installation_status.version
      })
      
      return
    end
  end

  logger.warn("Roslyn Language Server not found")
end

--- Check if C# Language Server is available in system PATH
--- @return string|nil path Path to executable or nil
function M._check_system_path()
  local commands = {
    "csharp-ls", "csharp-ls.exe",  -- csharp-ls (alternative C# language server)
    "Microsoft.CodeAnalysis.LanguageServer", "Microsoft.CodeAnalysis.LanguageServer.exe"  -- Roslyn
  }

  for _, cmd in ipairs(commands) do
    -- Use pcall to prevent errors from blocking startup
    local ok, result = pcall(function()
      return process.execute({ "where", cmd }, { timeout = 2000 })
    end)

    if ok and result.exit_code == 0 and #result.stdout > 0 then
      local path = result.stdout[1]:gsub("%s+$", "") -- trim whitespace
      if M._validate_server_executable(path) then
        return path
      end
    end
  end

  return nil
end

--- Check if Roslyn Language Server is installed via dotnet tool
--- @return string|nil path Path to executable or nil
function M._check_dotnet_tool()
  local os_name = M._get_os_name()
  local path_template = ROSLYN_PATHS.dotnet_tool[os_name]
  
  if not path_template then
    return nil
  end
  
  -- Expand environment variables
  local expanded_path = M._expand_path(path_template)
  
  if M._validate_server_executable(expanded_path) then
    return expanded_path
  end
  
  return nil
end

--- Check if Roslyn Language Server is available via VS Code extension
--- @return string|nil path Path to executable or nil
function M._check_vscode_extension()
  local os_name = M._get_os_name()
  local path_pattern = ROSLYN_PATHS.vscode_extension[os_name]
  
  if not path_pattern then
    return nil
  end
  
  -- Expand environment variables and find matching paths
  local base_path = M._expand_path(path_pattern:gsub("/[^/]*$", ""):gsub("\\[^\\]*$", ""))
  
  -- Look for VS Code C# extension directories
  local search_result = process.execute({ "find", base_path, "-name", "Microsoft.CodeAnalysis.LanguageServer*" }, { timeout = 5000 })
  
  if search_result.exit_code == 0 and #search_result.stdout > 0 then
    for _, path in ipairs(search_result.stdout) do
      local trimmed_path = path:gsub("%s+$", "")
      if M._validate_server_executable(trimmed_path) then
        return trimmed_path
      end
    end
  end
  
  return nil
end

--- Validate that a path points to a valid Roslyn Language Server executable
--- @param path string Path to validate
--- @return boolean valid True if path is valid executable
function M._validate_server_executable(path)
  if not path or path == "" then
    return false
  end

  -- Check if file exists and is executable
  local stat = vim.loop.fs_stat(path)
  if not stat or stat.type ~= "file" then
    return false
  end

  -- Try to run with --version to validate it's the right executable (with error handling)
  local ok, result = pcall(function()
    return process.execute({ path, "--version" }, { timeout = 2000 })
  end)

  return ok and result.exit_code == 0
end

--- Get the version of the Roslyn Language Server
--- @param path string Path to the executable
--- @return string|nil version Version string or nil
function M._get_server_version(path)
  local result = process.execute({ path, "--version" }, { timeout = 3000 })
  
  if result.exit_code == 0 and #result.stdout > 0 then
    -- Extract version from output
    local version_line = result.stdout[1]
    local version = version_line:match("(%d+%.%d+%.%d+)")
    return version
  end
  
  return nil
end

--- Install Roslyn Language Server automatically
--- @param method string|nil Installation method to use (optional)
--- @return boolean success True if installation was successful
function M.install(method)
  -- Check if already installed first
  if M.is_installed() then
    logger.info("Roslyn Language Server is already installed", {
      path = installation_status.path,
      version = installation_status.version,
      method = installation_status.installation_method
    })
    return true
  end

  method = method or INSTALLATION_METHODS.DOTNET_TOOL

  logger.info("Installing Roslyn Language Server", { method = method })

  if method == INSTALLATION_METHODS.DOTNET_TOOL then
    return M._install_via_dotnet_tool()
  elseif method == INSTALLATION_METHODS.MANUAL_DOWNLOAD then
    return M._install_via_manual_download()
  else
    logger.error("Unsupported installation method", { method = method })
    return false
  end
end

--- Install C# Language Server via dotnet tool
--- @return boolean success True if installation was successful
function M._install_via_dotnet_tool()
  logger.info("Installing C# Language Server via dotnet tool")

  -- Emit installation started event
  events.emit(events.EVENTS.LSP_INSTALLATION_STARTED, {
    method = INSTALLATION_METHODS.DOTNET_TOOL
  })

  -- Try installing both language servers for maximum compatibility
  local success = false

  -- First try csharp-ls (more reliable and lightweight)
  logger.info("Attempting to install csharp-ls...")
  local result1 = process.execute({
    "dotnet", "tool", "install", "--global", "csharp-ls"
  }, { timeout = 60000 })

  if result1.exit_code == 0 then
    logger.info("csharp-ls installed successfully")
    success = true
  else
    local stderr_text = table.concat(result1.stderr or {}, "\n"):lower()
    if stderr_text:match("already installed") then
      logger.info("csharp-ls is already installed")
      success = true
    else
      logger.warn("Failed to install csharp-ls: " .. table.concat(result1.stderr or {}, "\n"))
    end
  end

  -- Also try to install Microsoft Roslyn Language Server
  logger.info("Attempting to install Microsoft.CodeAnalysis.LanguageServer...")
  local result2 = process.execute({
    "dotnet", "tool", "install", "--global", "Microsoft.CodeAnalysis.LanguageServer"
  }, { timeout = 60000 })

  if result2.exit_code == 0 then
    logger.info("Microsoft.CodeAnalysis.LanguageServer installed successfully")
    success = true
  else
    local stderr_text2 = table.concat(result2.stderr or {}, "\n"):lower()
    if stderr_text2:match("already installed") then
      logger.info("Microsoft.CodeAnalysis.LanguageServer is already installed")
      success = true
    else
      logger.warn("Failed to install Microsoft.CodeAnalysis.LanguageServer: " .. table.concat(result2.stderr or {}, "\n"))
    end
  end

  if success then
    logger.info("C# Language Server installation completed successfully")

    -- Refresh installation status
    M._check_installation_status()

    -- Emit installation completed event
    events.emit(events.EVENTS.LSP_INSTALLATION_COMPLETED, {
      method = INSTALLATION_METHODS.DOTNET_TOOL,
      success = true,
      path = installation_status.path
    })

    return true
  else
    logger.error("Failed to install any C# Language Server via dotnet tool")

    -- Emit installation failed event
    events.emit(events.EVENTS.LSP_INSTALLATION_FAILED, {
      method = INSTALLATION_METHODS.DOTNET_TOOL,
      error = "Failed to install both csharp-ls and Microsoft.CodeAnalysis.LanguageServer"
    })

    return false
  end
end

--- Install Roslyn Language Server via manual download
--- @return boolean success True if installation was successful
function M._install_via_manual_download()
  logger.info("Manual download installation not yet implemented")
  -- TODO: Implement manual download and installation
  return false
end

--- Ensure Roslyn Language Server is installed
--- @return boolean success True if server is available after ensuring installation
function M.ensure_installed()
  -- Check if already installed
  if M.is_installed() then
    logger.debug("Roslyn Language Server already installed")
    return true
  end

  -- Check if auto-installation is enabled
  local lsp_config = config.get_value("lsp") or {}
  if not lsp_config.auto_install then
    logger.info("Roslyn Language Server not found and auto-installation is disabled")
    M._show_manual_installation_instructions()
    return false
  end

  logger.info("Roslyn Language Server not found, attempting automatic installation")

  -- Get preferred installation method from config
  local installation_config = lsp_config.installation or {}
  local method = installation_config.method or INSTALLATION_METHODS.DOTNET_TOOL

  -- Notify user if configured
  if installation_config.notify_user then
    vim.notify("Installing Roslyn Language Server...", vim.log.levels.INFO)
  end

  -- Try to install using configured method
  if M.install(method) then
    if installation_config.notify_user then
      vim.notify("Roslyn Language Server installed successfully!", vim.log.levels.INFO)
    end
    return true
  end

  -- If installation failed and retry is enabled, try alternative method
  if installation_config.auto_retry and method ~= INSTALLATION_METHODS.DOTNET_TOOL then
    logger.info("Retrying installation with dotnet tool method")
    if M.install(INSTALLATION_METHODS.DOTNET_TOOL) then
      if installation_config.notify_user then
        vim.notify("Roslyn Language Server installed successfully!", vim.log.levels.INFO)
      end
      return true
    end
  end

  -- If all installation attempts failed, provide helpful error message
  logger.error("Failed to automatically install Roslyn Language Server")
  if installation_config.notify_user then
    vim.notify("Failed to install Roslyn Language Server. See manual installation options in logs.", vim.log.levels.ERROR)
  end

  M._show_manual_installation_instructions()
  return false
end

--- Show manual installation instructions
function M._show_manual_installation_instructions()
  logger.info("Manual installation options:")
  logger.info("1. Install csharp-ls: dotnet tool install --global csharp-ls")
  logger.info("2. Install Microsoft Roslyn: dotnet tool install --global Microsoft.CodeAnalysis.LanguageServer")
  logger.info("3. Install VS Code C# extension (includes Roslyn Language Server)")
  logger.info("4. Download manually from GitHub releases")
  logger.info("5. Enable auto-installation: require('dotnet-plugin').setup({lsp={auto_install=true}})")
end

--- Get the operating system name
--- @return string os_name Operating system identifier
function M._get_os_name()
  if vim.fn.has("win32") == 1 then
    return "windows"
  elseif vim.fn.has("macunix") == 1 then
    return "macos"
  else
    return "linux"
  end
end

--- Expand environment variables in a path
--- @param path string Path with environment variables
--- @return string expanded_path Path with variables expanded
function M._expand_path(path)
  -- Simple environment variable expansion
  if vim.fn.has("win32") == 1 then
    -- Windows style %VAR%
    path = path:gsub("%%([^%%]+)%%", function(var)
      return vim.fn.getenv(var) or ""
    end)
  else
    -- Unix style $VAR
    path = path:gsub("$([A-Z_][A-Z0-9_]*)", function(var)
      return vim.fn.getenv(var) or ""
    end)
  end
  
  return path
end

--- Shutdown installer
function M.shutdown()
  if installer_initialized then
    logger.info("Shutting down Roslyn Language Server installer")
    installer_initialized = false
  end
end

return M
