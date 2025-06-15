-- dotnet-plugin.nvim - LSP Message Handlers
-- Solution context integration and enhanced message handling

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')
local solution_parser = require('dotnet-plugin.solution.parser')
local project_parser = require('dotnet-plugin.project.parser')

-- Handler state
local handlers_initialized = false
local original_handlers = {}

--- Initialize LSP message handlers
--- @return boolean success True if handlers were initialized successfully
function M.setup()
  if handlers_initialized then
    return true
  end

  logger.info("Initializing LSP message handlers with solution context")

  -- Setup enhanced handlers
  M._setup_enhanced_handlers()
  
  -- Setup solution context integration
  M._setup_solution_context()

  handlers_initialized = true
  logger.info("LSP message handlers initialized successfully")
  
  return true
end

--- Setup enhanced LSP message handlers
function M._setup_enhanced_handlers()
  -- Store original handlers for fallback
  original_handlers.definition = vim.lsp.handlers['textDocument/definition']
  original_handlers.references = vim.lsp.handlers['textDocument/references']
  original_handlers.completion = vim.lsp.handlers['textDocument/completion']
  original_handlers.hover = vim.lsp.handlers['textDocument/hover']

  -- Enhanced definition handler with cross-project navigation
  vim.lsp.handlers['textDocument/definition'] = function(err, result, ctx, config)
    if err then
      logger.error("LSP definition error", { error = err })
      return original_handlers.definition(err, result, ctx, config)
    end

    -- Enhance result with solution context
    result = M._enhance_definition_result(result, ctx)
    
    return original_handlers.definition(err, result, ctx, config)
  end

  -- Enhanced references handler with solution-wide search
  vim.lsp.handlers['textDocument/references'] = function(err, result, ctx, config)
    if err then
      logger.error("LSP references error", { error = err })
      return original_handlers.references(err, result, ctx, config)
    end

    -- Enhance result with cross-project references
    result = M._enhance_references_result(result, ctx)
    
    return original_handlers.references(err, result, ctx, config)
  end

  -- Enhanced completion handler with solution context
  vim.lsp.handlers['textDocument/completion'] = function(err, result, ctx, config)
    if err then
      logger.error("LSP completion error", { error = err })
      return original_handlers.completion(err, result, ctx, config)
    end

    -- Enhance completion with project-specific items
    result = M._enhance_completion_result(result, ctx)
    
    return original_handlers.completion(err, result, ctx, config)
  end

  -- Enhanced hover handler with additional context
  vim.lsp.handlers['textDocument/hover'] = function(err, result, ctx, config)
    if err then
      logger.error("LSP hover error", { error = err })
      return original_handlers.hover(err, result, ctx, config)
    end

    -- Enhance hover with solution context
    result = M._enhance_hover_result(result, ctx)
    
    return original_handlers.hover(err, result, ctx, config)
  end

  logger.debug("Enhanced LSP handlers registered")
end

--- Setup solution context integration
function M._setup_solution_context()
  -- Subscribe to solution events for context updates
  events.subscribe(events.EVENTS.SOLUTION_LOADED, function(data)
    M._update_solution_context(data)
  end)

  events.subscribe(events.EVENTS.PROJECT_CHANGED, function(data)
    M._update_project_context(data)
  end)
end

--- Enhance definition result with solution context
--- @param result table LSP definition result
--- @param ctx table LSP context
--- @return table enhanced_result Enhanced result with solution context
function M._enhance_definition_result(result, ctx)
  if not result or type(result) ~= "table" then
    return result
  end

  -- Add solution context to each definition location
  for i, location in ipairs(result) do
    if location.uri then
      local file_path = vim.uri_to_fname(location.uri)
      local project_info = M._get_project_info_for_file(file_path)
      
      if project_info then
        -- Add project context to the location
        location.project = {
          name = project_info.name,
          path = project_info.path,
          framework = project_info.target_framework
        }
      end
    end
  end

  logger.debug("Enhanced definition result with solution context", { 
    locations = #result 
  })

  return result
end

--- Enhance references result with cross-project search
--- @param result table LSP references result
--- @param ctx table LSP context
--- @return table enhanced_result Enhanced result with cross-project references
function M._enhance_references_result(result, ctx)
  if not result or type(result) ~= "table" then
    return result
  end

  -- Group references by project for better organization
  local by_project = {}
  
  for _, reference in ipairs(result) do
    if reference.uri then
      local file_path = vim.uri_to_fname(reference.uri)
      local project_info = M._get_project_info_for_file(file_path)
      
      if project_info then
        local project_name = project_info.name or "Unknown"
        
        if not by_project[project_name] then
          by_project[project_name] = {
            project = project_info,
            references = {}
          }
        end
        
        table.insert(by_project[project_name].references, reference)
      end
    end
  end

  -- Add project grouping information
  for _, reference in ipairs(result) do
    if reference.uri then
      local file_path = vim.uri_to_fname(reference.uri)
      local project_info = M._get_project_info_for_file(file_path)
      
      if project_info then
        reference.project = {
          name = project_info.name,
          path = project_info.path,
          framework = project_info.target_framework
        }
      end
    end
  end

  logger.debug("Enhanced references result with cross-project context", { 
    references = #result,
    projects = vim.tbl_count(by_project)
  })

  return result
end

--- Enhance completion result with project-specific items
--- @param result table LSP completion result
--- @param ctx table LSP context
--- @return table enhanced_result Enhanced completion with project context
function M._enhance_completion_result(result, ctx)
  if not result then
    return result
  end

  local items = result.items or result
  if not items or type(items) ~= "table" then
    return result
  end

  -- Get current file's project context
  local bufnr = ctx.bufnr
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project_info = M._get_project_info_for_file(file_path)

  if project_info then
    -- Add project-specific completion enhancements
    for _, item in ipairs(items) do
      -- Add project context to completion items
      if item.data then
        item.data.project = {
          name = project_info.name,
          framework = project_info.target_framework
        }
      end
      
      -- Enhance documentation with project context
      if item.documentation and project_info.name then
        local doc = item.documentation
        if type(doc) == "string" then
          item.documentation = doc .. "\n\n*Project: " .. project_info.name .. "*"
        elseif type(doc) == "table" and doc.value then
          doc.value = doc.value .. "\n\n*Project: " .. project_info.name .. "*"
        end
      end
    end
  end

  logger.debug("Enhanced completion result with project context", { 
    items = #items,
    project = project_info and project_info.name or "none"
  })

  return result
end

--- Enhance hover result with additional context
--- @param result table LSP hover result
--- @param ctx table LSP context
--- @return table enhanced_result Enhanced hover with solution context
function M._enhance_hover_result(result, ctx)
  if not result or not result.contents then
    return result
  end

  -- Get current file's project context
  local bufnr = ctx.bufnr
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project_info = M._get_project_info_for_file(file_path)

  if project_info then
    local contents = result.contents
    
    -- Add project context to hover information
    local project_context = string.format(
      "\n\n---\n**Project:** %s  \n**Framework:** %s",
      project_info.name or "Unknown",
      project_info.target_framework or "Unknown"
    )

    if type(contents) == "string" then
      result.contents = contents .. project_context
    elseif type(contents) == "table" then
      if contents.value then
        contents.value = contents.value .. project_context
      elseif #contents > 0 then
        local last_item = contents[#contents]
        if type(last_item) == "string" then
          contents[#contents] = last_item .. project_context
        elseif type(last_item) == "table" and last_item.value then
          last_item.value = last_item.value .. project_context
        end
      end
    end
  end

  logger.debug("Enhanced hover result with project context", { 
    project = project_info and project_info.name or "none"
  })

  return result
end

--- Get project information for a file
--- @param file_path string File path
--- @return table|nil project_info Project information or nil
function M._get_project_info_for_file(file_path)
  if not file_path then
    return nil
  end

  -- Try to get from cache first
  local cached_project = cache.get_project_for_file and cache.get_project_for_file(file_path)
  if cached_project then
    return cached_project
  end

  -- Find project file for this source file
  local dir = vim.fn.fnamemodify(file_path, ":p:h")
  local max_depth = 3
  local current_depth = 0

  while dir and current_depth < max_depth do
    local proj_files = vim.fn.glob(dir .. "/*.*proj", false, true)
    
    if #proj_files > 0 then
      -- Parse the first project file found
      local project_data = project_parser.parse_project(proj_files[1])
      if project_data then
        logger.debug("Found project for file", { 
          file = file_path, 
          project = project_data.name 
        })
        return project_data
      end
    end

    -- Move up one directory
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break -- Reached filesystem root
    end
    dir = parent
    current_depth = current_depth + 1
  end

  return nil
end

--- Update solution context
--- @param solution_data table Solution data
function M._update_solution_context(solution_data)
  logger.debug("Updating solution context for LSP handlers", { 
    solution = solution_data.name,
    projects = #(solution_data.projects or {})
  })

  -- Store solution context for handlers to use
  M.current_solution = solution_data
end

--- Update project context
--- @param project_data table Project data
function M._update_project_context(project_data)
  logger.debug("Updating project context for LSP handlers", { 
    project = project_data.name or project_data.path
  })

  -- Invalidate cached project info to force refresh
  if cache.invalidate_project_cache then
    cache.invalidate_project_cache(project_data.path)
  end
end

--- Get handler status
--- @return table status Handler status information
function M.get_status()
  return {
    initialized = handlers_initialized,
    enhanced_handlers = {
      definition = vim.lsp.handlers['textDocument/definition'] ~= original_handlers.definition,
      references = vim.lsp.handlers['textDocument/references'] ~= original_handlers.references,
      completion = vim.lsp.handlers['textDocument/completion'] ~= original_handlers.completion,
      hover = vim.lsp.handlers['textDocument/hover'] ~= original_handlers.hover
    },
    current_solution = M.current_solution and M.current_solution.name or nil
  }
end

--- Shutdown LSP handlers
function M.shutdown()
  if handlers_initialized then
    logger.info("Shutting down LSP handlers")
    
    -- Restore original handlers
    vim.lsp.handlers['textDocument/definition'] = original_handlers.definition
    vim.lsp.handlers['textDocument/references'] = original_handlers.references
    vim.lsp.handlers['textDocument/completion'] = original_handlers.completion
    vim.lsp.handlers['textDocument/hover'] = original_handlers.hover
    
    -- Clear state
    M.current_solution = nil
    handlers_initialized = false
    
    logger.info("LSP handlers shutdown complete")
  end
end

return M
