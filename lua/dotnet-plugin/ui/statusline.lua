-- Status line integration for dotnet-plugin.nvim
-- Provides .NET project and build status in the status line

local M = {}

local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')

-- Status line state
local statusline_initialized = false
local current_status = {
  solution = nil,
  project = nil,
  build_status = "idle", -- idle, building, success, error
  build_progress = nil,
  lsp_status = "inactive" -- inactive, starting, active, error
}

-- Status icons
local ICONS = {
  solution = "󰘐",
  project = "󰏗",
  build = {
    idle = "󰄬",
    building = "󰑮",
    success = "󰄬",
    error = "󰅚"
  },
  lsp = {
    inactive = "󰌘",
    starting = "󰔟",
    active = "󰌘",
    error = "󰅚"
  }
}

-- Status colors (highlight groups)
local HIGHLIGHTS = {
  normal = "StatusLine",
  success = "DiagnosticOk",
  warning = "DiagnosticWarn",
  error = "DiagnosticError",
  info = "DiagnosticInfo"
}

--- Setup status line integration
--- @return boolean success True if status line was initialized successfully
function M.setup()
  if statusline_initialized then
    return true
  end

  local statusline_config = config.get_value("ui.statusline") or {}
  
  if not statusline_config.enabled then
    logger.debug("Status line integration disabled in configuration")
    return true
  end

  logger.debug("Initializing status line integration")

  -- Setup status line function
  M._setup_statusline_function()
  
  -- Setup refresh timer if configured
  if statusline_config.auto_refresh then
    M._setup_refresh_timer(statusline_config.refresh_interval or 1000)
  end
  
  statusline_initialized = true
  logger.debug("Status line integration initialized")
  
  return true
end

--- Setup status line function
function M._setup_statusline_function()
  -- Create global function for status line
  _G.dotnet_statusline = function()
    return M.get_statusline_string()
  end
  
  -- Add to existing status line if configured
  local statusline_config = config.get_value("ui.statusline") or {}
  
  if statusline_config.integrate_with_existing then
    -- Try to integrate with popular status line plugins
    M._integrate_with_plugins()
  end
end

--- Integrate with popular status line plugins
function M._integrate_with_plugins()
  -- Try lualine integration
  local ok_lualine, lualine = pcall(require, 'lualine')
  if ok_lualine then
    M._integrate_with_lualine(lualine)
    return
  end
  
  -- Try galaxyline integration
  local ok_galaxyline = pcall(require, 'galaxyline')
  if ok_galaxyline then
    M._integrate_with_galaxyline()
    return
  end
  
  -- Fallback to manual integration
  logger.debug("No supported status line plugin found, use :set statusline+=%{v:lua.dotnet_statusline()}")
end

--- Integrate with lualine
--- @param lualine table Lualine module
function M._integrate_with_lualine(lualine)
  local config = lualine.get_config()
  
  -- Add dotnet component to lualine
  local dotnet_component = {
    function()
      return M.get_statusline_string()
    end,
    icon = ICONS.solution,
    color = function()
      local status = current_status.build_status
      if status == "error" then
        return { fg = vim.fn.synIDattr(vim.fn.hlID(HIGHLIGHTS.error), "fg") }
      elseif status == "success" then
        return { fg = vim.fn.synIDattr(vim.fn.hlID(HIGHLIGHTS.success), "fg") }
      elseif status == "building" then
        return { fg = vim.fn.synIDattr(vim.fn.hlID(HIGHLIGHTS.info), "fg") }
      else
        return { fg = vim.fn.synIDattr(vim.fn.hlID(HIGHLIGHTS.normal), "fg") }
      end
    end
  }
  
  -- Add to sections
  if config.sections and config.sections.lualine_c then
    table.insert(config.sections.lualine_c, dotnet_component)
    lualine.setup(config)
    logger.debug("Integrated with lualine")
  end
end

--- Integrate with galaxyline
function M._integrate_with_galaxyline()
  -- TODO: Implement galaxyline integration
  logger.debug("Galaxyline integration not yet implemented")
end

--- Setup refresh timer
--- @param interval number Refresh interval in milliseconds
function M._setup_refresh_timer(interval)
  local timer = vim.loop.new_timer()
  timer:start(interval, interval, vim.schedule_wrap(function()
    if statusline_initialized then
      vim.cmd('redrawstatus')
    end
  end))
end

--- Update solution status
--- @param solution_data table Solution information
function M.update_solution_status(solution_data)
  current_status.solution = {
    name = vim.fn.fnamemodify(solution_data.path, ":t:r"),
    path = solution_data.path,
    project_count = solution_data.projects and #solution_data.projects or 0
  }
  
  M._refresh_statusline()
  logger.debug("Solution status updated", { name = current_status.solution.name })
end

--- Clear solution status
function M.clear_solution_status()
  current_status.solution = nil
  current_status.project = nil
  M._refresh_statusline()
  logger.debug("Solution status cleared")
end

--- Update build status
--- @param status string Build status (idle, building, success, error)
--- @param data table|nil Build data
function M.update_build_status(status, data)
  current_status.build_status = status
  current_status.build_data = data
  
  M._refresh_statusline()
  logger.debug("Build status updated", { status = status })
end

--- Update build progress
--- @param progress_data table Build progress information
function M.update_build_progress(progress_data)
  current_status.build_progress = progress_data
  M._refresh_statusline()
end

--- Update LSP status
--- @param status string LSP status (inactive, starting, active, error)
function M.update_lsp_status(status)
  current_status.lsp_status = status
  M._refresh_statusline()
  logger.debug("LSP status updated", { status = status })
end

--- Get status line string
--- @return string Status line content
function M.get_statusline_string()
  if not statusline_initialized then
    return ""
  end
  
  local parts = {}
  local statusline_config = config.get_value("ui.statusline") or {}
  
  -- Solution info
  if current_status.solution and statusline_config.show_solution ~= false then
    local solution_part = string.format("%s %s", 
      ICONS.solution, 
      current_status.solution.name
    )
    
    if statusline_config.show_project_count and current_status.solution.project_count > 0 then
      solution_part = solution_part .. string.format(" (%d)", current_status.solution.project_count)
    end
    
    table.insert(parts, solution_part)
  end
  
  -- Build status
  if statusline_config.show_build_status ~= false then
    local build_icon = ICONS.build[current_status.build_status] or ICONS.build.idle
    local build_part = build_icon
    
    if current_status.build_status == "building" and current_status.build_progress then
      if current_status.build_progress.percentage then
        build_part = build_part .. string.format(" %d%%", current_status.build_progress.percentage)
      elseif current_status.build_progress.current and current_status.build_progress.total then
        build_part = build_part .. string.format(" %d/%d", 
          current_status.build_progress.current, 
          current_status.build_progress.total
        )
      end
    end
    
    table.insert(parts, build_part)
  end
  
  -- LSP status
  if statusline_config.show_lsp_status ~= false then
    local lsp_icon = ICONS.lsp[current_status.lsp_status] or ICONS.lsp.inactive
    table.insert(parts, lsp_icon)
  end
  
  if #parts == 0 then
    return ""
  end
  
  local separator = statusline_config.separator or " | "
  return table.concat(parts, separator)
end

--- Get detailed status information
--- @return table Detailed status data
function M.get_status()
  return vim.deepcopy(current_status)
end

--- Refresh status line display
function M._refresh_statusline()
  if statusline_initialized then
    vim.schedule(function()
      vim.cmd('redrawstatus')
    end)
  end
end

--- Refresh all status information
function M.refresh()
  -- Trigger refresh of all status components
  if current_status.solution then
    -- Re-emit solution loaded event to refresh data
    local events = require('dotnet-plugin.core.events')
    events.emit(events.EVENTS.SOLUTION_RELOAD_REQUESTED, { 
      path = current_status.solution.path 
    })
  end
  
  M._refresh_statusline()
  logger.debug("Status line refreshed")
end

--- Check if status line is showing .NET information
--- @return boolean True if .NET status is displayed
function M.is_active()
  return statusline_initialized and (
    current_status.solution ~= nil or 
    current_status.build_status ~= "idle" or
    current_status.lsp_status ~= "inactive"
  )
end

--- Shutdown status line integration
function M.shutdown()
  if statusline_initialized then
    -- Clear global function
    _G.dotnet_statusline = nil
    
    -- Clear status
    current_status = {
      solution = nil,
      project = nil,
      build_status = "idle",
      build_progress = nil,
      lsp_status = "inactive"
    }
    
    statusline_initialized = false
    logger.debug("Status line integration shutdown")
  end
end

return M
