-- File Operations Module for Enhanced Solution Explorer
-- Single Responsibility: Handles all file and folder operations

local M = {}

local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')

-- File operation types
M.OPERATIONS = {
  CREATE_FILE = "create_file",
  CREATE_FOLDER = "create_folder",
  RENAME = "rename",
  DELETE = "delete",
  COPY = "copy",
  MOVE = "move"
}

-- File templates
M.FILE_TEMPLATES = {
  {name = "Class", extension = "cs", template = "class"},
  {name = "Interface", extension = "cs", template = "interface"},
  {name = "Enum", extension = "cs", template = "enum"},
  {name = "Record", extension = "cs", template = "record"},
  {name = "Controller", extension = "cs", template = "controller"},
  {name = "Service", extension = "cs", template = "service"},
  {name = "Model", extension = "cs", template = "model"},
  {name = "Configuration", extension = "json", template = "config"}
}

--- Initialize file operations manager
--- @param opts table|nil Configuration options
--- @return boolean success
function M.setup(opts)
  logger.debug("File operations manager initialized")
  return true
end

--- Create file from template
--- @param parent_path string Parent directory path
--- @param template table File template
--- @param file_name string File name
--- @return boolean success
function M.create_file(parent_path, template, file_name)
  if not parent_path or not template or not file_name then
    logger.error("Invalid parameters for file creation")
    return false
  end
  
  -- Ensure file has correct extension
  if not file_name:match("%." .. template.extension .. "$") then
    file_name = file_name .. "." .. template.extension
  end
  
  local file_path = parent_path .. "/" .. file_name
  
  -- Check if file already exists
  if vim.fn.filereadable(file_path) == 1 then
    logger.warn("File already exists: " .. file_path)
    return false
  end
  
  -- Generate content from template
  local content = M._generate_file_content(template, file_name, parent_path)
  
  -- Create file
  local success = M._write_file(file_path, content)
  if success then
    logger.info("Created file: " .. file_path)
    
    -- Emit file created event
    events.emit("file_created", { file_path = file_path })
    
    return true
  else
    logger.error("Failed to create file: " .. file_path)
    return false
  end
end

--- Create folder
--- @param parent_path string Parent directory path
--- @param folder_name string Folder name
--- @return boolean success
function M.create_folder(parent_path, folder_name)
  if not parent_path or not folder_name then
    logger.error("Invalid parameters for folder creation")
    return false
  end
  
  local folder_path = parent_path .. "/" .. folder_name
  
  -- Check if folder already exists
  if vim.fn.isdirectory(folder_path) == 1 then
    logger.warn("Folder already exists: " .. folder_path)
    return false
  end
  
  -- Create folder
  local success = vim.fn.mkdir(folder_path, "p") == 1
  if success then
    logger.info("Created folder: " .. folder_path)
    
    -- Emit folder created event
    events.emit("folder_created", { folder_path = folder_path })
    
    return true
  else
    logger.error("Failed to create folder: " .. folder_path)
    return false
  end
end

--- Rename file or folder
--- @param old_path string Current path
--- @param new_name string New name
--- @return boolean success
function M.rename(old_path, new_name)
  if not old_path or not new_name then
    logger.error("Invalid parameters for rename operation")
    return false
  end
  
  local parent_dir = vim.fn.fnamemodify(old_path, ":h")
  local new_path = parent_dir .. "/" .. new_name
  
  -- Check if target already exists
  if vim.fn.filereadable(new_path) == 1 or vim.fn.isdirectory(new_path) == 1 then
    logger.warn("Target already exists: " .. new_path)
    return false
  end
  
  -- Perform rename
  local success = vim.fn.rename(old_path, new_path) == 0
  if success then
    logger.info("Renamed: " .. old_path .. " -> " .. new_path)
    
    -- Emit rename event
    events.emit("file_renamed", { 
      old_path = old_path, 
      new_path = new_path 
    })
    
    return true
  else
    logger.error("Failed to rename: " .. old_path)
    return false
  end
end

--- Delete file or folder
--- @param path string Path to delete
--- @return boolean success
function M.delete(path)
  if not path then
    logger.error("Invalid path for delete operation")
    return false
  end
  
  -- Confirm deletion
  local item_type = vim.fn.isdirectory(path) == 1 and "folder" or "file"
  local confirm_msg = string.format("Delete %s '%s'?", item_type, vim.fn.fnamemodify(path, ":t"))
  
  local choice = vim.fn.confirm(confirm_msg, "&Yes\n&No", 2)
  if choice ~= 1 then
    return false
  end
  
  -- Perform deletion
  local success
  if item_type == "folder" then
    success = vim.fn.delete(path, "rf") == 0
  else
    success = vim.fn.delete(path) == 0
  end
  
  if success then
    logger.info("Deleted: " .. path)
    
    -- Emit delete event
    events.emit("file_deleted", { file_path = path })
    
    return true
  else
    logger.error("Failed to delete: " .. path)
    return false
  end
end

--- Generate file content from template
--- @param template table File template
--- @param file_name string File name
--- @param parent_path string Parent directory path
--- @return string content
function M._generate_file_content(template, file_name, parent_path)
  local class_name = vim.fn.fnamemodify(file_name, ':r')
  local namespace = M._get_namespace_for_path(parent_path)
  
  local templates = {
    class = string.format([[namespace %s;

public class %s
{
    
}]], namespace, class_name),
    
    interface = string.format([[namespace %s;

public interface %s
{
    
}]], namespace, class_name),
    
    enum = string.format([[namespace %s;

public enum %s
{
    
}]], namespace, class_name),
    
    record = string.format([[namespace %s;

public record %s
{
    
}]], namespace, class_name),
    
    controller = string.format([[using Microsoft.AspNetCore.Mvc;

namespace %s.Controllers;

[ApiController]
[Route("api/[controller]")]
public class %s : ControllerBase
{
    
}]], namespace, class_name),
    
    service = string.format([[namespace %s.Services;

public class %s
{
    
}]], namespace, class_name),
    
    model = string.format([[namespace %s.Models;

public class %s
{
    
}]], namespace, class_name),
    
    config = [[{
  
}]]
  }
  
  return templates[template.template] or ""
end

--- Get namespace for a given path
--- @param path string Directory path
--- @return string namespace
function M._get_namespace_for_path(path)
  -- Find the nearest project file
  local project_file = M._find_project_file(path)
  if project_file then
    local project_name = vim.fn.fnamemodify(project_file, ':t:r')
    return project_name
  end
  
  return "MyNamespace"
end

--- Find project file for a given path
--- @param path string Directory path
--- @return string|nil project_file
function M._find_project_file(path)
  local current_dir = path
  
  while current_dir ~= '/' and current_dir ~= '' do
    local project_files = vim.fn.glob(current_dir .. '/*.{csproj,fsproj,vbproj}', false, true)
    if #project_files > 0 then
      return project_files[1]
    end
    current_dir = vim.fn.fnamemodify(current_dir, ':h')
  end
  
  return nil
end

--- Write content to file
--- @param file_path string File path
--- @param content string File content
--- @return boolean success
function M._write_file(file_path, content)
  local file = io.open(file_path, 'w')
  if not file then
    return false
  end
  
  file:write(content)
  file:close()
  return true
end

--- Get available file templates
--- @return table templates
function M.get_file_templates()
  return vim.deepcopy(M.FILE_TEMPLATES)
end

return M
