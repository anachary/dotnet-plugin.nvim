-- dotnet-plugin.nvim - File Watcher Event Filters
-- Filter and process file change events to avoid unnecessary processing

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')

-- File extensions we care about
local WATCHED_EXTENSIONS = {
  ['.sln'] = true,      -- Solution files
  ['.csproj'] = true,   -- C# project files
  ['.fsproj'] = true,   -- F# project files
  ['.vbproj'] = true,   -- VB.NET project files
  ['.props'] = true,    -- MSBuild property files
  ['.targets'] = true,  -- MSBuild target files
}

-- Events we care about
local RELEVANT_EVENTS = {
  ['change'] = true,    -- File content changed
  ['rename'] = true,    -- File renamed/moved
}

-- Temporary file patterns to ignore
local IGNORE_PATTERNS = {
  '%.tmp$',           -- Temporary files
  '%.bak$',           -- Backup files
  '%.swp$',           -- Vim swap files
  '%.swo$',           -- Vim swap files
  '%~$',              -- Editor temporary files
  '^%.#',             -- Emacs lock files
  '%.lock$',          -- Lock files
  '%.log$',           -- Log files
}

-- Directories to ignore
local IGNORE_DIRECTORIES = {
  'bin',
  'obj',
  '.vs',
  '.vscode',
  'node_modules',
  '.git',
  '.svn',
  '.hg',
}

--- Check if a file change event should be processed
--- @param file_path string Full path to the file being watched
--- @param filename string|nil Name of the changed file (may be nil)
--- @param events table Event information from fs_event
--- @return boolean should_process True if the event should be processed
function M.should_process_event(file_path, filename, events)
  -- If no filename provided, use the watched file path
  local target_file = filename and (vim.fn.fnamemodify(file_path, ':h') .. '/' .. filename) or file_path
  
  logger.debug("Filtering file event", {
    file_path = file_path,
    filename = filename,
    target_file = target_file,
    events = events
  })

  -- Check if the event type is relevant
  if not M._is_relevant_event(events) then
    logger.debug("Ignoring irrelevant event type", { events = events })
    return false
  end

  -- Check if the file extension is watched
  if not M._is_watched_file(target_file) then
    logger.debug("Ignoring unwatched file type", { file = target_file })
    return false
  end

  -- Check if the file should be ignored based on patterns
  if M._should_ignore_file(target_file) then
    logger.debug("Ignoring filtered file", { file = target_file })
    return false
  end

  -- Check if the file is in an ignored directory
  if M._is_in_ignored_directory(target_file) then
    logger.debug("Ignoring file in ignored directory", { file = target_file })
    return false
  end

  logger.debug("Event passed all filters", { file = target_file })
  return true
end

--- Check if the event type is relevant to us
--- @param events table Event information
--- @return boolean is_relevant True if the event is relevant
function M._is_relevant_event(events)
  if not events then
    return false
  end

  -- Handle both string and table event formats
  if type(events) == 'string' then
    return RELEVANT_EVENTS[events] == true
  end

  if type(events) == 'table' then
    for _, event in ipairs(events) do
      if RELEVANT_EVENTS[event] then
        return true
      end
    end
  end

  return false
end

--- Check if a file should be watched based on its extension
--- @param file_path string Path to the file
--- @return boolean should_watch True if the file should be watched
function M._is_watched_file(file_path)
  local extension = vim.fn.fnamemodify(file_path, ':e')
  if extension == '' then
    return false
  end
  
  return WATCHED_EXTENSIONS['.' .. extension:lower()] == true
end

--- Check if a file should be ignored based on patterns
--- @param file_path string Path to the file
--- @return boolean should_ignore True if the file should be ignored
function M._should_ignore_file(file_path)
  local filename = vim.fn.fnamemodify(file_path, ':t')
  
  for _, pattern in ipairs(IGNORE_PATTERNS) do
    if filename:match(pattern) then
      return true
    end
  end
  
  return false
end

--- Check if a file is in an ignored directory
--- @param file_path string Path to the file
--- @return boolean is_ignored True if the file is in an ignored directory
function M._is_in_ignored_directory(file_path)
  local dir_parts = vim.split(file_path, '/', { plain = true })
  
  for _, part in ipairs(dir_parts) do
    for _, ignored_dir in ipairs(IGNORE_DIRECTORIES) do
      if part:lower() == ignored_dir:lower() then
        return true
      end
    end
  end
  
  return false
end

--- Add a custom file extension to watch
--- @param extension string File extension (with or without leading dot)
function M.add_watched_extension(extension)
  if not extension:match('^%.') then
    extension = '.' .. extension
  end
  
  WATCHED_EXTENSIONS[extension:lower()] = true
  logger.debug("Added watched extension", { extension = extension })
end

--- Remove a file extension from watching
--- @param extension string File extension (with or without leading dot)
function M.remove_watched_extension(extension)
  if not extension:match('^%.') then
    extension = '.' .. extension
  end
  
  WATCHED_EXTENSIONS[extension:lower()] = nil
  logger.debug("Removed watched extension", { extension = extension })
end

--- Add a custom ignore pattern
--- @param pattern string Lua pattern to ignore
function M.add_ignore_pattern(pattern)
  table.insert(IGNORE_PATTERNS, pattern)
  logger.debug("Added ignore pattern", { pattern = pattern })
end

--- Add a directory to ignore
--- @param directory string Directory name to ignore
function M.add_ignored_directory(directory)
  table.insert(IGNORE_DIRECTORIES, directory:lower())
  logger.debug("Added ignored directory", { directory = directory })
end

--- Get current filter configuration
--- @return table config Current filter settings
function M.get_filter_config()
  return {
    watched_extensions = vim.tbl_keys(WATCHED_EXTENSIONS),
    relevant_events = vim.tbl_keys(RELEVANT_EVENTS),
    ignore_patterns = vim.deepcopy(IGNORE_PATTERNS),
    ignore_directories = vim.deepcopy(IGNORE_DIRECTORIES)
  }
end

--- Reset filters to default configuration
function M.reset_filters()
  -- Reset to default watched extensions
  WATCHED_EXTENSIONS = {
    ['.sln'] = true,
    ['.csproj'] = true,
    ['.fsproj'] = true,
    ['.vbproj'] = true,
    ['.props'] = true,
    ['.targets'] = true,
  }
  
  -- Reset ignore patterns to defaults
  IGNORE_PATTERNS = {
    '%.tmp$',
    '%.bak$',
    '%.swp$',
    '%.swo$',
    '%~$',
    '^%.#',
    '%.lock$',
    '%.log$',
  }
  
  -- Reset ignore directories to defaults
  IGNORE_DIRECTORIES = {
    'bin',
    'obj',
    '.vs',
    '.vscode',
    'node_modules',
    '.git',
    '.svn',
    '.hg',
  }
  
  logger.debug("File filters reset to defaults")
end

return M
