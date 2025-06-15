-- Configuration system for dotnet-plugin.nvim
-- Provides user-customizable settings with validation and defaults

local M = {}

-- Default configuration schema
local DEFAULT_CONFIG = {
  -- .NET CLI settings
  dotnet_path = {
    type = "string",
    default = "dotnet",
    description = "Path to dotnet executable"
  },
  
  -- MSBuild settings
  msbuild_path = {
    type = "string",
    default = "msbuild",
    description = "Path to MSBuild executable"
  },
  
  -- Cache settings
  cache = {
    type = "table",
    default = {
      enabled = true,
      path = function() return vim.fn.stdpath("cache") .. "/dotnet-plugin" end,
      max_age_days = 30,
      cleanup_on_startup = true
    },
    description = "JSON file-based cache configuration"
  },

  -- File watcher settings
  watchers = {
    type = "table",
    default = {
      enabled = true,
      auto_watch_solutions = true,
      auto_watch_projects = true,
      auto_reload_on_change = false,
      reload_delay_ms = 500,
      dependency_analysis_delay_ms = 1000
    },
    description = "File watcher configuration for real-time updates"
  },

  -- Legacy cache path (deprecated, use cache.path instead)
  solution_cache_path = {
    type = "string",
    default = function() return vim.fn.stdpath("cache") .. "/dotnet-plugin/solution" end,
    description = "Path to solution cache directory (deprecated)"
  },
  
  -- Build settings
  max_parallel_builds = {
    type = "number",
    default = 4,
    min = 1,
    max = 16,
    description = "Maximum number of parallel project builds"
  },
  
  -- Logging settings
  logging = {
    type = "table",
    default = {
      level = "info",
      file_enabled = true,
      buffer_enabled = false,
      file_path = function() return vim.fn.stdpath("cache") .. "/dotnet-plugin/dotnet-plugin.log" end
    },
    description = "Logging configuration"
  },
  
  -- Solution settings
  solution = {
    type = "table",
    default = {
      auto_detect = true,
      search_depth = 3,
      cache_enabled = true,
      watch_files = true
    },
    description = "Solution management settings"
  },
  
  -- Project settings
  project = {
    type = "table",
    default = {
      auto_restore = true,
      build_on_save = false,
      default_configuration = "Debug",
      default_platform = "AnyCPU"
    },
    description = "Project management settings"
  },

  -- LSP settings
  lsp = {
    type = "table",
    default = {
      enabled = true,
      server = "roslyn",  -- Only Roslyn Language Server for enterprise optimization
      auto_start = true,
      auto_attach = true,
      workspace_folders = true,
      auto_install = true,  -- Automatically install C# Language Server if not found
      installation = {
        method = "dotnet_tool",  -- Preferred installation method
        timeout = 60000,  -- Installation timeout in milliseconds
        auto_retry = true,  -- Retry installation on failure
        notify_user = true  -- Show installation progress to user
      },
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
    description = "Roslyn Language Server configuration for enterprise solutions with automatic installation"
  },

  -- UI settings
  ui = {
    type = "table",
    default = {
      enabled = true,
      solution_explorer = {
        enabled = true,
        width = 30,
        position = "left",  -- left, right
        keymaps = {
          toggle = "<leader>se"
        }
      },
      statusline = {
        enabled = true,
        show_solution = true,
        show_project_count = true,
        show_build_status = true,
        show_lsp_status = true,
        separator = " | ",
        integrate_with_existing = true,
        auto_refresh = true,
        refresh_interval = 1000
      },
      notifications = {
        enabled = true,
        backend = "auto",  -- auto, nvim-notify, fidget, vim
        error_timeout = 5000,
        warn_timeout = 3000,
        info_timeout = 2000
      }
    },
    description = "UI components configuration"
  },

  -- Build settings
  build = {
    type = "table",
    default = {
      enabled = true,
      msbuild_path = "dotnet",
      configuration = "Debug",
      platform = nil,
      verbosity = "minimal",  -- quiet, minimal, normal, detailed, diagnostic
      max_parallel_builds = 4,
      no_restore = false,
      auto_restore_on_load = true,
      auto_build_on_change = false,
      auto_build_on_save = false,
      auto_open_quickfix = true,
      show_progress_notifications = true,
      show_error_notifications = true
    },
    description = "Build system configuration"
  }
}

-- Current configuration
local current_config = {}

--- Validate a configuration value against its schema
--- @param key string Configuration key
--- @param value any Value to validate
--- @param schema table Schema definition
--- @return boolean, string|nil Valid, error message
local function validate_value(key, value, schema)
  if schema.type == "string" then
    if type(value) ~= "string" then
      return false, string.format("Expected string for '%s', got %s", key, type(value))
    end
  elseif schema.type == "number" then
    if type(value) ~= "number" then
      return false, string.format("Expected number for '%s', got %s", key, type(value))
    end
    if schema.min and value < schema.min then
      return false, string.format("Value for '%s' must be >= %d", key, schema.min)
    end
    if schema.max and value > schema.max then
      return false, string.format("Value for '%s' must be <= %d", key, schema.max)
    end
  elseif schema.type == "boolean" then
    if type(value) ~= "boolean" then
      return false, string.format("Expected boolean for '%s', got %s", key, type(value))
    end
  elseif schema.type == "table" then
    if type(value) ~= "table" then
      return false, string.format("Expected table for '%s', got %s", key, type(value))
    end
  end
  
  return true, nil
end

--- Get default value for a configuration key
--- @param schema table Schema definition
--- @return any Default value
local function get_default_value(schema)
  if type(schema.default) == "function" then
    return schema.default()
  else
    return schema.default
  end
end

--- Deep merge two tables
--- @param target table Target table
--- @param source table Source table
--- @return table Merged table
local function deep_merge(target, source)
  local result = vim.deepcopy(target)
  
  for key, value in pairs(source) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = deep_merge(result[key], value)
    else
      result[key] = value
    end
  end
  
  return result
end

--- Setup configuration with user options
--- @param user_config table User configuration
function M.setup(user_config)
  -- Start with defaults
  local config = {}
  
  for key, schema in pairs(DEFAULT_CONFIG) do
    config[key] = get_default_value(schema)
  end
  
  -- Merge user configuration
  if user_config then
    config = deep_merge(config, user_config)
  end
  
  -- Validate configuration
  for key, value in pairs(config) do
    local schema = DEFAULT_CONFIG[key]
    if schema then
      local valid, error_msg = validate_value(key, value, schema)
      if not valid then
        error(string.format("Configuration validation failed: %s", error_msg))
      end
    end
  end
  
  current_config = config
end

--- Get current configuration
--- @return table Current configuration
function M.get()
  return current_config
end

--- Get a specific configuration value
--- @param key string Configuration key (supports dot notation)
--- @return any Configuration value
function M.get_value(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = current_config
  
  for _, k in ipairs(keys) do
    if type(value) == "table" and value[k] ~= nil then
      value = value[k]
    else
      return nil
    end
  end
  
  return value
end

--- Update a configuration value
--- @param key string Configuration key (supports dot notation)
--- @param value any New value
function M.set_value(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local target = current_config
  
  for i = 1, #keys - 1 do
    local k = keys[i]
    if type(target[k]) ~= "table" then
      target[k] = {}
    end
    target = target[k]
  end
  
  target[keys[#keys]] = value
end

--- Get configuration schema
--- @return table Configuration schema
function M.get_schema()
  return DEFAULT_CONFIG
end

return M
