-- File system utilities for dotnet-plugin.nvim
-- Provides file system operations and path utilities

local M = {}

local logger = require('dotnet-plugin.core.logger')

--- Check if a path exists
--- @param path string Path to check
--- @return boolean Path exists
function M.exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

--- Check if a path is a file
--- @param path string Path to check
--- @return boolean Is file
function M.is_file(path)
  return vim.fn.filereadable(path) == 1
end

--- Check if a path is a directory
--- @param path string Path to check
--- @return boolean Is directory
function M.is_directory(path)
  return vim.fn.isdirectory(path) == 1
end

--- Get file extension
--- @param path string File path
--- @return string File extension (without dot)
function M.get_extension(path)
  return vim.fn.fnamemodify(path, ":e"):lower()
end

--- Get file name without extension
--- @param path string File path
--- @return string File name without extension
function M.get_name(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

--- Get directory name
--- @param path string File path
--- @return string Directory path
function M.get_directory(path)
  return vim.fn.fnamemodify(path, ":h")
end

--- Join path components
--- @param ... string Path components
--- @return string Joined path
function M.join(...)
  local parts = { ... }
  local path = parts[1] or ""
  
  for i = 2, #parts do
    local part = parts[i]
    if part and part ~= "" then
      if path:sub(-1) == "/" or path:sub(-1) == "\\" then
        path = path .. part
      else
        path = path .. "/" .. part
      end
    end
  end
  
  return path
end

--- Normalize path separators
--- @param path string Path to normalize
--- @return string Normalized path
function M.normalize(path)
  if vim.fn.has("win32") == 1 then
    return path:gsub("/", "\\")
  else
    return path:gsub("\\", "/")
  end
end

--- Get relative path
--- @param path string Absolute path
--- @param base string Base directory
--- @return string Relative path
function M.relative(path, base)
  base = base or vim.fn.getcwd()
  
  -- Normalize paths
  path = vim.fn.resolve(path)
  base = vim.fn.resolve(base)
  
  -- Use Vim's built-in function
  return vim.fn.fnamemodify(path, ":~:.")
end

--- Create directory recursively
--- @param path string Directory path
--- @return boolean Success
function M.mkdir(path)
  local success = vim.fn.mkdir(path, "p")
  if success == 0 then
    logger.error("Failed to create directory", { path = path })
    return false
  end
  return true
end

--- Read file contents
--- @param path string File path
--- @return string[]|nil File lines or nil on error
function M.read_file(path)
  if not M.is_file(path) then
    return nil
  end
  
  local lines = vim.fn.readfile(path)
  return lines
end

--- Write file contents
--- @param path string File path
--- @param lines string[] File lines
--- @return boolean Success
function M.write_file(path, lines)
  local dir = M.get_directory(path)
  if not M.exists(dir) then
    if not M.mkdir(dir) then
      return false
    end
  end
  
  local success = vim.fn.writefile(lines, path)
  if success ~= 0 then
    logger.error("Failed to write file", { path = path })
    return false
  end
  
  return true
end

--- Find files matching a pattern
--- @param directory string Directory to search
--- @param pattern string File pattern (glob)
--- @param recursive boolean|nil Search recursively (default: false)
--- @return string[] List of matching files
function M.find_files(directory, pattern, recursive)
  if not M.is_directory(directory) then
    return {}
  end
  
  local search_pattern = directory .. "/" .. pattern
  if recursive then
    search_pattern = directory .. "/**/" .. pattern
  end
  
  local files = vim.fn.glob(search_pattern, false, true)
  return files
end

--- Find directories matching a pattern
--- @param directory string Directory to search
--- @param pattern string Directory pattern (glob)
--- @param recursive boolean|nil Search recursively (default: false)
--- @return string[] List of matching directories
function M.find_directories(directory, pattern, recursive)
  if not M.is_directory(directory) then
    return {}
  end
  
  local search_pattern = directory .. "/" .. pattern
  if recursive then
    search_pattern = directory .. "/**/" .. pattern
  end
  
  local dirs = vim.fn.glob(search_pattern, false, true)
  return vim.tbl_filter(function(path)
    return M.is_directory(path)
  end, dirs)
end

--- Get file modification time
--- @param path string File path
--- @return number|nil Modification time or nil if file doesn't exist
function M.get_mtime(path)
  if not M.exists(path) then
    return nil
  end
  
  return vim.fn.getftime(path)
end

--- Check if file is newer than another
--- @param file1 string First file path
--- @param file2 string Second file path
--- @return boolean File1 is newer than file2
function M.is_newer(file1, file2)
  local mtime1 = M.get_mtime(file1)
  local mtime2 = M.get_mtime(file2)
  
  if not mtime1 or not mtime2 then
    return false
  end
  
  return mtime1 > mtime2
end

--- Watch a file or directory for changes
--- @param path string Path to watch
--- @param callback function Callback function
--- @return number|nil Watcher handle or nil on error
function M.watch(path, callback)
  if not M.exists(path) then
    logger.error("Cannot watch non-existent path", { path = path })
    return nil
  end
  
  local handle = vim.loop.fs_event_start(path, {}, function(err, filename, events)
    if err then
      logger.error("File watch error", { error = err, path = path })
      return
    end
    
    vim.schedule(function()
      callback(filename, events)
    end)
  end)
  
  if not handle then
    logger.error("Failed to start file watcher", { path = path })
    return nil
  end
  
  logger.debug("Started file watcher", { path = path })
  return handle
end

--- Stop watching a file or directory
--- @param handle number Watcher handle
function M.unwatch(handle)
  if handle then
    vim.loop.fs_event_stop(handle)
    logger.debug("Stopped file watcher")
  end
end

--- Get current working directory
--- @return string Current working directory
function M.cwd()
  return vim.fn.getcwd()
end

--- Change current working directory
--- @param path string New working directory
--- @return boolean Success
function M.chdir(path)
  if not M.is_directory(path) then
    logger.error("Cannot change to non-existent directory", { path = path })
    return false
  end
  
  vim.cmd("cd " .. vim.fn.fnameescape(path))
  return true
end

--- Get temporary directory
--- @return string Temporary directory path
function M.temp_dir()
  return vim.fn.tempname()
end

--- Create temporary file
--- @param suffix string|nil File suffix
--- @return string Temporary file path
function M.temp_file(suffix)
  local temp_path = vim.fn.tempname()
  if suffix then
    temp_path = temp_path .. suffix
  end
  return temp_path
end

--- Check if path is absolute
--- @param path string Path to check
--- @return boolean Is absolute path
function M.is_absolute(path)
  if vim.fn.has("win32") == 1 then
    return path:match("^[A-Za-z]:[/\\]") ~= nil
  else
    return path:sub(1, 1) == "/"
  end
end

--- Convert to absolute path
--- @param path string Path to convert
--- @param base string|nil Base directory (default: cwd)
--- @return string Absolute path
function M.absolute(path, base)
  if M.is_absolute(path) then
    return path
  end
  
  base = base or M.cwd()
  return vim.fn.resolve(M.join(base, path))
end

return M
