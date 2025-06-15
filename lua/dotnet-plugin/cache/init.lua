-- dotnet-plugin.nvim - Cache Management
-- Reliable JSON file-based caching system

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local json_cache = require('dotnet-plugin.cache.json_cache')

-- Cache state
local cache_initialized = false

--- Initialize the cache system
--- @return boolean success True if cache was initialized successfully
function M.setup()
  if cache_initialized then
    return true
  end

  local cache_config = config.get_value("cache") or {}
  local cache_path = cache_config.path

  -- Handle function-based default values
  if type(cache_path) == "function" then
    cache_path = cache_path()
  elseif not cache_path then
    cache_path = vim.fn.stdpath("cache") .. "/dotnet-plugin"
  end

  -- Initialize JSON cache
  local success = json_cache.setup({
    path = cache_path,
    max_age_days = cache_config.max_age_days or 30
  })

  if success then
    cache_initialized = true
    logger.info("JSON file cache system initialized successfully", { path = cache_path })
  else
    logger.error("Failed to initialize JSON file cache system")
  end

  return success
end

--- Check if cache is available and initialized
--- @return boolean available True if cache is ready for use
function M.is_available()
  return cache_initialized and json_cache.is_available()
end

--- Get cached solution data
--- @param solution_path string Path to the solution file
--- @return table|nil solution_data Cached solution data or nil if not found/expired
function M.get_solution(solution_path)
  return json_cache.get_solution(solution_path)
end

--- Store solution data in cache
--- @param solution_path string Path to the solution file
--- @param solution_data table Solution data to cache
--- @return boolean success True if data was cached successfully
function M.set_solution(solution_path, solution_data)
  return json_cache.set_solution(solution_path, solution_data)
end

--- Get cached project data
--- @param project_path string Path to the project file
--- @return table|nil project_data Cached project data or nil if not found/expired
function M.get_project(project_path)
  return json_cache.get_project(project_path)
end

--- Store project data in cache
--- @param project_path string Path to the project file
--- @param project_data table Project data to cache
--- @return boolean success True if data was cached successfully
function M.set_project(project_path, project_data)
  return json_cache.set_project(project_path, project_data)
end

--- Invalidate cache entry for a specific path
--- @param file_path string Path to invalidate
--- @return boolean success True if invalidation was successful
function M.invalidate(file_path)
  return json_cache.invalidate(file_path)
end

--- Clean up old cache entries
--- @param max_age_days number Maximum age in days (default: 30)
--- @return boolean success True if cleanup was successful
function M.cleanup(max_age_days)
  return json_cache.cleanup(max_age_days)
end

--- Get cache statistics
--- @return table stats Cache usage statistics
function M.get_stats()
  return json_cache.get_stats()
end

--- Get solution root directory for a file (for LSP workspace detection)
--- @param file_path string File path
--- @return string|nil solution_root Solution root directory or nil
function M.get_solution_root(file_path)
  -- This is a helper function for LSP client to quickly find solution roots
  -- It could be enhanced to use cached solution data for faster lookups
  return json_cache.get_solution_root and json_cache.get_solution_root(file_path) or nil
end

--- Shutdown cache system
function M.shutdown()
  json_cache.shutdown()
  cache_initialized = false
  logger.debug("JSON cache system shutdown")
end

return M
