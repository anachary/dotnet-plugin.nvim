-- Solution file parser for dotnet-plugin.nvim
-- Parses .sln files and extracts project information

local M = {}

local logger = require('dotnet-plugin.core.logger')
local cache = require('dotnet-plugin.cache')
local config = require('dotnet-plugin.core.config')

--- Solution information
--- @class Solution
--- @field path string Solution file path
--- @field name string Solution name
--- @field format_version string Solution format version
--- @field visual_studio_version string Visual Studio version
--- @field projects Project[] List of projects
--- @field solution_folders SolutionFolder[] List of solution folders

--- Project information
--- @class Project
--- @field id string Project GUID
--- @field name string Project name
--- @field path string Project file path (relative to solution)
--- @field type_id string Project type GUID
--- @field type string Project type (library, exe, etc.)
--- @field dependencies string[] List of project dependencies

--- Solution folder information
--- @class SolutionFolder
--- @field id string Folder GUID
--- @field name string Folder name
--- @field items string[] List of items in folder

-- Project type GUIDs
local PROJECT_TYPES = {
  ["FAE04EC0-301F-11D3-BF4B-00C04F79EFBC"] = "csharp",
  ["F184B08F-C81C-45F6-A57F-5ABD9991F28F"] = "vb",
  ["F2A71F9B-5D33-465A-A702-920D77279786"] = "fsharp",
  ["8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942"] = "cpp",
  ["2150E333-8FDC-42A3-9474-1A3956D46DE8"] = "folder"
}

--- Parse a solution file
--- @param solution_path string Path to solution file
--- @param use_cache boolean|nil Whether to use cache (default: true)
--- @return Solution|nil Parsed solution or nil on error
function M.parse_solution(solution_path, use_cache)
  if not vim.fn.filereadable(solution_path) then
    logger.error("Solution file not found", { path = solution_path })
    return nil
  end

  -- Check cache first (unless explicitly disabled)
  use_cache = use_cache ~= false and config.get_value("cache.enabled")
  if use_cache then
    local cached_solution = cache.get_solution(solution_path)
    if cached_solution then
      logger.debug("Using cached solution data", { path = solution_path })
      return cached_solution
    end
  end

  logger.debug("Parsing solution file", { path = solution_path })

  local lines = vim.fn.readfile(solution_path)
  if not lines or #lines == 0 then
    logger.error("Failed to read solution file", { path = solution_path })
    return nil
  end
  
  local solution = {
    path = solution_path,
    name = vim.fn.fnamemodify(solution_path, ":t:r"),
    format_version = "",
    visual_studio_version = "",
    projects = {},
    solution_folders = {}
  }
  
  local i = 1
  while i <= #lines do
    local line = vim.trim(lines[i])
    
    -- Parse format version
    if line:match("^Microsoft Visual Studio Solution File") then
      local format_match = line:match("Format Version ([%d%.]+)")
      if format_match then
        solution.format_version = format_match
      end
    end
    
    -- Parse Visual Studio version
    if line:match("^# Visual Studio") then
      solution.visual_studio_version = line:match("^# (.+)$") or ""
    end
    
    -- Parse project
    if line:match("^Project%(") then
      local project = M.parse_project_line(line)
      if project then
        -- Resolve project path relative to solution
        local solution_dir = vim.fn.fnamemodify(solution_path, ":h")
        project.path = vim.fn.resolve(solution_dir .. "/" .. project.path)
        
        -- Determine project type
        project.type = PROJECT_TYPES[project.type_id] or "unknown"
        
        table.insert(solution.projects, project)
        
        -- Parse project dependencies
        i = i + 1
        while i <= #lines do
          local dep_line = vim.trim(lines[i])
          if dep_line == "EndProject" then
            break
          end
          
          -- Parse project dependencies section
          if dep_line:match("ProjectSection%(ProjectDependencies%)") then
            i = i + 1
            while i <= #lines do
              local proj_dep_line = vim.trim(lines[i])
              if proj_dep_line == "EndProjectSection" then
                break
              end
              
              local dep_id = proj_dep_line:match("^{([^}]+)}")
              if dep_id then
                table.insert(project.dependencies, dep_id)
              end
              
              i = i + 1
            end
          end
          
          i = i + 1
        end
      end
    end
    
    i = i + 1
  end
  
  logger.debug("Solution parsed successfully", {
    path = solution_path,
    project_count = #solution.projects
  })

  -- Cache the parsed solution (if caching is enabled)
  if use_cache then
    cache.set_solution(solution_path, solution)
  end

  return solution
end

--- Parse a project line from solution file
--- @param line string Project line
--- @return Project|nil Parsed project or nil on error
function M.parse_project_line(line)
  -- Project("{type_id}") = "name", "path", "{project_id}"
  local type_id, name, path, project_id = line:match(
    'Project%(\"({[^}]+})\"%)%s*=%s*\"([^\"]+)\",%s*\"([^\"]+)\",%s*\"({[^}]+})\"'
  )
  
  if not type_id or not name or not path or not project_id then
    logger.warn("Failed to parse project line", { line = line })
    return nil
  end
  
  return {
    id = project_id:sub(2, -2), -- Remove braces
    name = name,
    path = path,
    type_id = type_id:sub(2, -2), -- Remove braces
    type = "unknown",
    dependencies = {}
  }
end

--- Find solution files in a directory
--- @param directory string Directory to search
--- @param max_depth number|nil Maximum search depth (default: 3)
--- @return string[] List of solution file paths
function M.find_solutions(directory, max_depth)
  max_depth = max_depth or 3
  local solutions = {}
  
  local function search_directory(dir, depth)
    if depth > max_depth then
      return
    end
    
    local items = vim.fn.glob(dir .. "/*", false, true)
    for _, item in ipairs(items) do
      if vim.fn.isdirectory(item) == 1 then
        -- Skip common directories that won't contain solutions
        local dirname = vim.fn.fnamemodify(item, ":t")
        if not vim.tbl_contains({ "bin", "obj", "node_modules", ".git", ".vs" }, dirname) then
          search_directory(item, depth + 1)
        end
      elseif item:match("%.sln$") then
        table.insert(solutions, item)
      end
    end
  end
  
  search_directory(directory, 1)
  return solutions
end

--- Get project type from project file
--- @param project_path string Path to project file
--- @return string Project type
function M.get_project_type(project_path)
  local ext = vim.fn.fnamemodify(project_path, ":e"):lower()
  
  if ext == "csproj" then
    return "csharp"
  elseif ext == "vbproj" then
    return "vb"
  elseif ext == "fsproj" then
    return "fsharp"
  elseif ext == "vcxproj" then
    return "cpp"
  else
    return "unknown"
  end
end

--- Validate solution structure
--- @param solution Solution Solution to validate
--- @return boolean, string[] Valid, list of errors
function M.validate_solution(solution)
  local errors = {}
  
  if not solution.path or solution.path == "" then
    table.insert(errors, "Solution path is empty")
  end
  
  if not solution.name or solution.name == "" then
    table.insert(errors, "Solution name is empty")
  end
  
  -- Check if all project files exist
  for _, project in ipairs(solution.projects) do
    if not vim.fn.filereadable(project.path) then
      table.insert(errors, string.format("Project file not found: %s", project.path))
    end
  end
  
  return #errors == 0, errors
end

return M
