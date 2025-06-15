-- dotnet-plugin.nvim - JSON File-Based Cache System
-- Reliable caching without external dependencies

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local fs = require('dotnet-plugin.utils.fs')

-- Cache state
local cache_dir = nil
local cache_initialized = false
local cache_stats = {
  available = false,
  solutions = 0,
  projects = 0,
  cache_path = nil
}

--- Initialize the JSON cache system
--- @param config table Cache configuration
--- @return boolean success True if cache was initialized successfully
function M.setup(config)
  if cache_initialized then
    return true
  end

  config = config or {}
  
  -- Set up cache directory
  cache_dir = config.path or (vim.fn.stdpath("cache") .. "/dotnet-plugin")
  
  -- Create cache directory if it doesn't exist
  if not fs.mkdir(cache_dir) then
    logger.error("Failed to create cache directory", { path = cache_dir })
    return false
  end

  -- Create subdirectories for different cache types
  local subdirs = { "solutions", "projects", "metadata" }
  for _, subdir in ipairs(subdirs) do
    local subdir_path = cache_dir .. "/" .. subdir
    if not fs.mkdir(subdir_path) then
      logger.warn("Failed to create cache subdirectory", { path = subdir_path })
    end
  end

  -- Update cache stats
  cache_stats.available = true
  cache_stats.cache_path = cache_dir
  
  -- Count existing cache files
  M._update_stats()

  cache_initialized = true
  logger.info("JSON file cache initialized", { path = cache_dir })
  return true
end

--- Check if cache is available
--- @return boolean available True if cache is ready for use
function M.is_available()
  return cache_initialized and cache_stats.available
end

--- Get cache statistics
--- @return table stats Cache statistics
function M.get_stats()
  if not M.is_available() then
    return { available = false }
  end
  
  M._update_stats()
  return vim.deepcopy(cache_stats)
end

--- Get cached solution data
--- @param solution_path string Path to the solution file
--- @return table|nil solution_data Cached solution data or nil if not found/expired
function M.get_solution(solution_path)
  if not M.is_available() then
    return nil
  end

  local cache_key = M._get_cache_key(solution_path)
  local cache_file = cache_dir .. "/solutions/" .. cache_key .. ".json"
  
  -- Check if cache file exists
  if vim.fn.filereadable(cache_file) == 0 then
    logger.debug("Solution cache miss", { path = solution_path })
    return nil
  end

  -- Check if source file is newer than cache
  local source_mtime = vim.fn.getftime(solution_path)
  local cache_mtime = vim.fn.getftime(cache_file)
  
  if source_mtime > cache_mtime then
    logger.debug("Solution cache expired", { path = solution_path })
    -- Remove expired cache file
    vim.fn.delete(cache_file)
    return nil
  end

  -- Read and parse cache file
  local cache_data = M._read_cache_file(cache_file)
  if cache_data then
    logger.debug("Solution cache hit", { path = solution_path })
    return cache_data.data
  end

  return nil
end

--- Cache solution data
--- @param solution_path string Path to the solution file
--- @param solution_data table Solution data to cache
--- @return boolean success True if data was cached successfully
function M.set_solution(solution_path, solution_data)
  if not M.is_available() then
    return false
  end

  local cache_key = M._get_cache_key(solution_path)
  local cache_file = cache_dir .. "/solutions/" .. cache_key .. ".json"
  
  local cache_entry = {
    version = "1.0",
    timestamp = os.time(),
    source_path = solution_path,
    source_mtime = vim.fn.getftime(solution_path),
    data = solution_data
  }

  local success = M._write_cache_file(cache_file, cache_entry)
  if success then
    logger.debug("Solution cached", { path = solution_path, cache_file = cache_file })
    M._update_stats()
  end
  
  return success
end

--- Get cached project data
--- @param project_path string Path to the project file
--- @return table|nil project_data Cached project data or nil if not found/expired
function M.get_project(project_path)
  if not M.is_available() then
    return nil
  end

  local cache_key = M._get_cache_key(project_path)
  local cache_file = cache_dir .. "/projects/" .. cache_key .. ".json"
  
  -- Check if cache file exists
  if vim.fn.filereadable(cache_file) == 0 then
    logger.debug("Project cache miss", { path = project_path })
    return nil
  end

  -- Check if source file is newer than cache
  local source_mtime = vim.fn.getftime(project_path)
  local cache_mtime = vim.fn.getftime(cache_file)
  
  if source_mtime > cache_mtime then
    logger.debug("Project cache expired", { path = project_path })
    -- Remove expired cache file
    vim.fn.delete(cache_file)
    return nil
  end

  -- Read and parse cache file
  local cache_data = M._read_cache_file(cache_file)
  if cache_data then
    logger.debug("Project cache hit", { path = project_path })
    return cache_data.data
  end

  return nil
end

--- Cache project data
--- @param project_path string Path to the project file
--- @param project_data table Project data to cache
--- @return boolean success True if data was cached successfully
function M.set_project(project_path, project_data)
  if not M.is_available() then
    return false
  end

  local cache_key = M._get_cache_key(project_path)
  local cache_file = cache_dir .. "/projects/" .. cache_key .. ".json"
  
  local cache_entry = {
    version = "1.0",
    timestamp = os.time(),
    source_path = project_path,
    source_mtime = vim.fn.getftime(project_path),
    data = project_data
  }

  local success = M._write_cache_file(cache_file, cache_entry)
  if success then
    logger.debug("Project cached", { path = project_path, cache_file = cache_file })
    M._update_stats()
  end
  
  return success
end

--- Invalidate cache for a specific file
--- @param file_path string Path to invalidate
--- @return boolean success True if invalidation was successful
function M.invalidate(file_path)
  if not M.is_available() then
    return false
  end

  local cache_key = M._get_cache_key(file_path)
  local invalidated = false
  
  -- Check both solution and project cache directories
  local cache_files = {
    cache_dir .. "/solutions/" .. cache_key .. ".json",
    cache_dir .. "/projects/" .. cache_key .. ".json"
  }
  
  for _, cache_file in ipairs(cache_files) do
    if vim.fn.filereadable(cache_file) == 1 then
      vim.fn.delete(cache_file)
      invalidated = true
      logger.debug("Cache invalidated", { file = cache_file })
    end
  end
  
  if invalidated then
    M._update_stats()
  end
  
  return invalidated
end

--- Cleanup old cache entries
--- @param max_age_days number|nil Maximum age in days (default: 30)
--- @return boolean success True if cleanup was successful
function M.cleanup(max_age_days)
  if not M.is_available() then
    return false
  end

  max_age_days = max_age_days or 30
  local cutoff_time = os.time() - (max_age_days * 24 * 60 * 60)
  local cleaned_count = 0
  
  -- Cleanup solutions
  local solutions_dir = cache_dir .. "/solutions"
  cleaned_count = cleaned_count + M._cleanup_directory(solutions_dir, cutoff_time)
  
  -- Cleanup projects
  local projects_dir = cache_dir .. "/projects"
  cleaned_count = cleaned_count + M._cleanup_directory(projects_dir, cutoff_time)
  
  logger.info("Cache cleanup completed", { 
    files_removed = cleaned_count,
    max_age_days = max_age_days
  })
  
  M._update_stats()
  return true
end

--- Generate cache key from file path
--- @param file_path string File path
--- @return string cache_key Safe cache key
function M._get_cache_key(file_path)
  -- Normalize path and create safe filename
  local normalized = vim.fn.fnamemodify(file_path, ':p'):gsub('\\', '/'):lower()
  -- Replace unsafe characters with underscores
  local safe_key = normalized:gsub('[^%w%-%.]', '_')
  -- Limit length and add hash for uniqueness
  if #safe_key > 100 then
    local hash = vim.fn.sha256(normalized):sub(1, 8)
    safe_key = safe_key:sub(1, 90) .. '_' .. hash
  end
  return safe_key
end

--- Read and parse cache file
--- @param cache_file string Path to cache file
--- @return table|nil cache_data Parsed cache data or nil on error
function M._read_cache_file(cache_file)
  local lines = fs.read_file(cache_file)
  if not lines then
    return nil
  end

  -- Join lines back into a single string
  local content = table.concat(lines, "\n")

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    logger.warn("Failed to parse cache file", { file = cache_file, error = data })
    -- Remove corrupted cache file
    vim.fn.delete(cache_file)
    return nil
  end

  return data
end

--- Write cache data to file
--- @param cache_file string Path to cache file
--- @param cache_data table Data to cache
--- @return boolean success True if write was successful
function M._write_cache_file(cache_file, cache_data)
  local ok, json_content = pcall(vim.json.encode, cache_data)
  if not ok then
    logger.error("Failed to encode cache data", { file = cache_file, error = json_content })
    return false
  end

  -- Convert JSON string to lines for fs.write_file
  local lines = vim.split(json_content, "\n", { plain = true })
  return fs.write_file(cache_file, lines)
end

--- Update cache statistics
function M._update_stats()
  if not M.is_available() then
    return
  end

  -- Count solution cache files
  local solutions_dir = cache_dir .. "/solutions"
  cache_stats.solutions = M._count_files_in_directory(solutions_dir)
  
  -- Count project cache files
  local projects_dir = cache_dir .. "/projects"
  cache_stats.projects = M._count_files_in_directory(projects_dir)
end

--- Count files in directory
--- @param dir_path string Directory path
--- @return number count Number of files
function M._count_files_in_directory(dir_path)
  if vim.fn.isdirectory(dir_path) == 0 then
    return 0
  end

  local files = vim.fn.glob(dir_path .. "/*.json", false, true)
  return #files
end

--- Cleanup old files in directory
--- @param dir_path string Directory path
--- @param cutoff_time number Cutoff timestamp
--- @return number cleaned_count Number of files removed
function M._cleanup_directory(dir_path, cutoff_time)
  if vim.fn.isdirectory(dir_path) == 0 then
    return 0
  end

  local files = vim.fn.glob(dir_path .. "/*.json", false, true)
  local cleaned_count = 0
  
  for _, file in ipairs(files) do
    local mtime = vim.fn.getftime(file)
    if mtime < cutoff_time then
      vim.fn.delete(file)
      cleaned_count = cleaned_count + 1
    end
  end
  
  return cleaned_count
end

--- Shutdown cache system
function M.shutdown()
  if cache_initialized then
    logger.debug("JSON cache system shutdown")
    cache_initialized = false
    cache_stats.available = false
  end
end

return M
