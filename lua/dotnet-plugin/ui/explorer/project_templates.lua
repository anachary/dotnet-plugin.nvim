-- Project Templates Module for Enhanced Solution Explorer
-- Single Responsibility: Manages .NET project templates and creation

local M = {}

local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')
local process = require('dotnet-plugin.core.process')
local events = require('dotnet-plugin.core.events')

-- Project templates
M.TEMPLATES = {
  {
    name = "Console Application",
    template = "console",
    framework = "net8.0",
    description = "A simple console application",
    category = "Application"
  },
  {
    name = "Class Library",
    template = "classlib",
    framework = "net8.0",
    description = "A reusable class library",
    category = "Library"
  },
  {
    name = "Web API",
    template = "webapi",
    framework = "net8.0",
    description = "ASP.NET Core Web API",
    category = "Web"
  },
  {
    name = "MVC Web App",
    template = "mvc",
    framework = "net8.0",
    description = "ASP.NET Core MVC application",
    category = "Web"
  },
  {
    name = "Blazor Server",
    template = "blazorserver",
    framework = "net8.0",
    description = "Blazor Server application",
    category = "Web"
  },
  {
    name = "Worker Service",
    template = "worker",
    framework = "net8.0",
    description = "Background service application",
    category = "Service"
  },
  {
    name = "xUnit Test Project",
    template = "xunit",
    framework = "net8.0",
    description = "xUnit test project",
    category = "Test"
  },
  {
    name = "NUnit Test Project",
    template = "nunit",
    framework = "net8.0",
    description = "NUnit test project",
    category = "Test"
  }
}

--- Initialize project templates manager
--- @param opts table|nil Configuration options
--- @return boolean success
function M.setup(opts)
  logger.debug("Project templates manager initialized")
  return true
end

--- Get available project templates
--- @param category string|nil Filter by category
--- @return table templates
function M.get_templates(category)
  if not category then
    return vim.deepcopy(M.TEMPLATES)
  end
  
  local filtered = {}
  for _, template in ipairs(M.TEMPLATES) do
    if template.category == category then
      table.insert(filtered, vim.deepcopy(template))
    end
  end
  
  return filtered
end

--- Get template by name
--- @param template_name string Template name
--- @return table|nil template
function M.get_template_by_name(template_name)
  for _, template in ipairs(M.TEMPLATES) do
    if template.name == template_name then
      return vim.deepcopy(template)
    end
  end
  return nil
end

--- Create project from template
--- @param template table Project template
--- @param project_name string Project name
--- @param output_dir string Output directory
--- @param options table|nil Additional options
--- @return boolean success
function M.create_project(template, project_name, output_dir, options)
  if not template or not project_name or not output_dir then
    logger.error("Invalid parameters for project creation")
    return false
  end
  
  options = options or {}
  
  -- Validate project name
  local valid, error_msg = M.validate_project_name(project_name)
  if not valid then
    logger.error("Invalid project name: " .. error_msg)
    return false
  end
  
  local project_dir = output_dir .. "/" .. project_name
  
  -- Check if directory already exists
  if vim.fn.isdirectory(project_dir) == 1 then
    logger.warn("Project directory already exists: " .. project_dir)
    return false
  end
  
  -- Build dotnet new command
  local cmd = M._build_create_command(template, project_name, project_dir, options)
  
  logger.info("Creating project: " .. project_name)
  logger.debug("Command: " .. table.concat(cmd, " "))
  
  -- Execute project creation
  process.run_async(cmd, {
    on_exit = function(result)
      M._handle_project_creation_result(result, template, project_name, project_dir)
    end
  })
  
  return true
end

--- Build dotnet new command
--- @param template table Project template
--- @param project_name string Project name
--- @param project_dir string Project directory
--- @param options table Additional options
--- @return table command
function M._build_create_command(template, project_name, project_dir, options)
  local cmd = {
    config.get_value("dotnet_path") or "dotnet",
    "new", template.template,
    "--name", project_name,
    "--output", project_dir
  }
  
  -- Add framework if specified
  if template.framework then
    table.insert(cmd, "--framework")
    table.insert(cmd, template.framework)
  end
  
  return cmd
end

--- Handle project creation result
--- @param result table Command result
--- @param template table Project template
--- @param project_name string Project name
--- @param project_dir string Project directory
function M._handle_project_creation_result(result, template, project_name, project_dir)
  if result.success then
    logger.info("Project created successfully: " .. project_name)
    
    -- Emit project created event
    events.emit("project_created", {
      template = template,
      project_name = project_name,
      project_dir = project_dir,
      project_file = project_dir .. "/" .. project_name .. ".csproj"
    })
    
  else
    logger.error("Failed to create project: " .. project_name)
    logger.debug("Error: " .. (result.stderr or "Unknown error"))
    
    -- Emit project creation failed event
    events.emit("project_creation_failed", {
      template = template,
      project_name = project_name,
      error = result.stderr
    })
  end
end

--- Validate project name
--- @param name string Project name
--- @return boolean valid
--- @return string|nil error_message
function M.validate_project_name(name)
  if not name or name == "" then
    return false, "Project name cannot be empty"
  end
  
  -- Check length
  if #name > 100 then
    return false, "Project name is too long (max 100 characters)"
  end
  
  -- Check for invalid characters
  local invalid_chars = '[<>:"/\\|?*%s]'
  if name:match(invalid_chars) then
    return false, "Project name contains invalid characters or spaces"
  end
  
  -- Must start with letter or underscore
  if not name:match("^[a-zA-Z_]") then
    return false, "Project name must start with a letter or underscore"
  end
  
  return true
end

--- Check if dotnet CLI is available
--- @return boolean available
function M.is_dotnet_available()
  local dotnet_path = config.get_value("dotnet_path") or "dotnet"
  return vim.fn.executable(dotnet_path) == 1
end

return M
