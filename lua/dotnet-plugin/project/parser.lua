-- Project file parser for dotnet-plugin.nvim
-- Parses .csproj, .fsproj, and .vbproj files

local M = {}

local logger = require('dotnet-plugin.core.logger')
local cache = require('dotnet-plugin.cache')
local config = require('dotnet-plugin.core.config')

--- Project information
--- @class ProjectInfo
--- @field path string Project file path
--- @field name string Project name
--- @field type string Project type (library, exe, etc.)
--- @field framework string Target framework
--- @field frameworks string[] Target frameworks (for multi-targeting)
--- @field output_type string Output type (Library, Exe, WinExe, etc.)
--- @field assembly_name string Assembly name
--- @field root_namespace string Root namespace
--- @field package_references PackageReference[] NuGet package references
--- @field project_references ProjectReference[] Project references
--- @field compile_items string[] Source files
--- @field content_items string[] Content files
--- @field properties table Additional properties

--- Package reference information
--- @class PackageReference
--- @field name string Package name
--- @field version string Package version
--- @field include_assets string|nil Include assets
--- @field exclude_assets string|nil Exclude assets

--- Project reference information
--- @class ProjectReference
--- @field path string Referenced project path
--- @field name string|nil Referenced project name

--- Parse a project file
--- @param project_path string Path to project file
--- @param use_cache boolean|nil Whether to use cache (default: true)
--- @return ProjectInfo|nil Parsed project or nil on error
function M.parse_project(project_path, use_cache)
  if not vim.fn.filereadable(project_path) then
    logger.error("Project file not found", { path = project_path })
    return nil
  end

  -- Check cache first (unless explicitly disabled)
  use_cache = use_cache ~= false and config.get_value("cache.enabled")
  if use_cache then
    local cached_project = cache.get_project(project_path)
    if cached_project then
      logger.debug("Using cached project data", { path = project_path })
      return cached_project
    end
  end

  logger.debug("Parsing project file", { path = project_path })

  local content = table.concat(vim.fn.readfile(project_path), "\n")
  if not content or content == "" then
    logger.error("Failed to read project file", { path = project_path })
    return nil
  end
  
  local project = {
    path = project_path,
    name = vim.fn.fnamemodify(project_path, ":t:r"),
    type = "unknown",
    framework = "",
    frameworks = {},
    output_type = "",
    assembly_name = "",
    root_namespace = "",
    package_references = {},
    project_references = {},
    compile_items = {},
    content_items = {},
    properties = {}
  }
  
  -- Determine if this is SDK-style or legacy project
  local is_sdk_style = content:match('<Project%s+Sdk=') ~= nil
  
  if is_sdk_style then
    M.parse_sdk_style_project(content, project)
  else
    M.parse_legacy_project(content, project)
  end
  
  -- Resolve project references relative to project directory
  local project_dir = vim.fn.fnamemodify(project_path, ":h")
  for _, ref in ipairs(project.project_references) do
    ref.path = vim.fn.resolve(project_dir .. "/" .. ref.path)
    if not ref.name then
      ref.name = vim.fn.fnamemodify(ref.path, ":t:r")
    end
  end
  
  logger.debug("Project parsed successfully", {
    path = project_path,
    framework = project.framework,
    package_count = #project.package_references,
    reference_count = #project.project_references
  })

  -- Cache the parsed project (if caching is enabled)
  if use_cache then
    cache.set_project(project_path, project)
  end

  return project
end

--- Parse SDK-style project file
--- @param content string Project file content
--- @param project ProjectInfo Project information to populate
function M.parse_sdk_style_project(content, project)
  -- Extract target framework(s)
  local target_framework = content:match("<TargetFramework>([^<]+)</TargetFramework>")
  local target_frameworks = content:match("<TargetFrameworks>([^<]+)</TargetFrameworks>")
  
  if target_frameworks then
    project.frameworks = vim.split(target_frameworks, ";", { plain = true })
    project.framework = project.frameworks[1] or ""
  elseif target_framework then
    project.framework = target_framework
    project.frameworks = { target_framework }
  end
  
  -- Extract output type
  project.output_type = content:match("<OutputType>([^<]+)</OutputType>") or "Library"
  
  -- Extract assembly name
  project.assembly_name = content:match("<AssemblyName>([^<]+)</AssemblyName>") or project.name
  
  -- Extract root namespace
  project.root_namespace = content:match("<RootNamespace>([^<]+)</RootNamespace>") or project.name
  
  -- Parse package references
  for package_ref in content:gmatch('<PackageReference[^>]*>.-</PackageReference>') do
    local package = M.parse_package_reference(package_ref)
    if package then
      table.insert(project.package_references, package)
    end
  end
  
  -- Parse self-closing package references
  for package_ref in content:gmatch('<PackageReference[^/>]*/[^>]*>') do
    local package = M.parse_package_reference(package_ref)
    if package then
      table.insert(project.package_references, package)
    end
  end
  
  -- Parse project references
  for proj_ref in content:gmatch('<ProjectReference[^>]*Include="([^"]+)"') do
    table.insert(project.project_references, {
      path = proj_ref,
      name = nil
    })
  end
  
  -- Determine project type based on output type and framework
  if project.output_type == "Exe" or project.output_type == "WinExe" then
    project.type = "exe"
  else
    project.type = "library"
  end
end

--- Parse legacy project file
--- @param content string Project file content
--- @param project ProjectInfo Project information to populate
function M.parse_legacy_project(content, project)
  -- Extract target framework version
  local framework_version = content:match("<TargetFrameworkVersion>v([^<]+)</TargetFrameworkVersion>")
  if framework_version then
    project.framework = "net" .. framework_version:gsub("%.", "")
    project.frameworks = { project.framework }
  end
  
  -- Extract output type
  project.output_type = content:match("<OutputType>([^<]+)</OutputType>") or "Library"
  
  -- Extract assembly name
  project.assembly_name = content:match("<AssemblyName>([^<]+)</AssemblyName>") or project.name
  
  -- Extract root namespace
  project.root_namespace = content:match("<RootNamespace>([^<]+)</RootNamespace>") or project.name
  
  -- Parse package references (packages.config style)
  for package_ref in content:gmatch('<PackageReference[^>]*>.-</PackageReference>') do
    local package = M.parse_package_reference(package_ref)
    if package then
      table.insert(project.package_references, package)
    end
  end
  
  -- Parse project references
  for proj_ref in content:gmatch('<ProjectReference[^>]*Include="([^"]+)"') do
    table.insert(project.project_references, {
      path = proj_ref,
      name = nil
    })
  end
  
  -- Parse compile items
  for compile_item in content:gmatch('<Compile[^>]*Include="([^"]+)"') do
    table.insert(project.compile_items, compile_item)
  end
  
  -- Parse content items
  for content_item in content:gmatch('<Content[^>]*Include="([^"]+)"') do
    table.insert(project.content_items, content_item)
  end
  
  -- Determine project type
  if project.output_type == "Exe" or project.output_type == "WinExe" then
    project.type = "exe"
  else
    project.type = "library"
  end
end

--- Parse a package reference element
--- @param element string Package reference XML element
--- @return PackageReference|nil Parsed package reference
function M.parse_package_reference(element)
  local name = element:match('Include="([^"]+)"')
  if not name then
    return nil
  end
  
  local version = element:match('Version="([^"]+)"') or element:match('<Version>([^<]+)</Version>')
  if not version then
    return nil
  end
  
  local include_assets = element:match('IncludeAssets="([^"]+)"') or element:match('<IncludeAssets>([^<]+)</IncludeAssets>')
  local exclude_assets = element:match('ExcludeAssets="([^"]+)"') or element:match('<ExcludeAssets>([^<]+)</ExcludeAssets>')
  
  return {
    name = name,
    version = version,
    include_assets = include_assets,
    exclude_assets = exclude_assets
  }
end

--- Get project dependencies (both package and project references)
--- @param project ProjectInfo Project information
--- @return table Dependencies with types
function M.get_dependencies(project)
  local dependencies = {
    packages = {},
    projects = {}
  }
  
  for _, pkg in ipairs(project.package_references) do
    table.insert(dependencies.packages, {
      name = pkg.name,
      version = pkg.version,
      type = "package"
    })
  end
  
  for _, proj in ipairs(project.project_references) do
    table.insert(dependencies.projects, {
      name = proj.name or vim.fn.fnamemodify(proj.path, ":t:r"),
      path = proj.path,
      type = "project"
    })
  end
  
  return dependencies
end

--- Check if project supports a specific framework
--- @param project ProjectInfo Project information
--- @param framework string Framework to check
--- @return boolean Supports framework
function M.supports_framework(project, framework)
  for _, fw in ipairs(project.frameworks) do
    if fw == framework then
      return true
    end
  end
  return false
end

--- Get project output path
--- @param project ProjectInfo Project information
--- @param configuration string|nil Build configuration (default: Debug)
--- @param framework string|nil Target framework
--- @return string Output path
function M.get_output_path(project, configuration, framework)
  configuration = configuration or "Debug"
  framework = framework or project.framework
  
  local project_dir = vim.fn.fnamemodify(project.path, ":h")
  local output_dir = project_dir .. "/bin/" .. configuration
  
  if framework and framework ~= "" then
    output_dir = output_dir .. "/" .. framework
  end
  
  local extension = project.output_type == "Library" and ".dll" or ".exe"
  return output_dir .. "/" .. project.assembly_name .. extension
end

return M
