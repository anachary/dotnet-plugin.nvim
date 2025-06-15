-- dotnet-plugin.nvim - IntelliSense Features
-- Enhanced code completion and navigation with solution context

local M = {}

-- Import dependencies
local logger = require('dotnet-plugin.core.logger')
local config = require('dotnet-plugin.core.config')
local events = require('dotnet-plugin.core.events')
local cache = require('dotnet-plugin.cache')

-- IntelliSense state
local intellisense_initialized = false
local completion_cache = {}
local symbol_cache = {}

--- Initialize IntelliSense features
--- @return boolean success True if IntelliSense was initialized successfully
function M.setup()
  if intellisense_initialized then
    return true
  end

  logger.info("Initializing enhanced IntelliSense features")

  -- Setup completion enhancements
  M._setup_completion_enhancements()
  
  -- Setup navigation features
  M._setup_navigation_features()
  
  -- Setup symbol search
  M._setup_symbol_search()
  
  -- Setup diagnostic enhancements
  M._setup_diagnostic_enhancements()

  intellisense_initialized = true
  logger.info("IntelliSense features initialized successfully")
  
  return true
end

--- Setup completion enhancements
function M._setup_completion_enhancements()
  -- Enhanced completion with solution context
  vim.api.nvim_create_autocmd('CompleteDone', {
    group = vim.api.nvim_create_augroup('DotnetIntelliSense', { clear = true }),
    pattern = '*.cs,*.fs,*.vb',
    callback = function()
      M._on_completion_done()
    end
  })

  -- Setup completion item resolve enhancement
  local original_resolve = vim.lsp.buf.completion
  
  vim.lsp.buf.completion = function(context)
    -- Enhance context with solution information
    local enhanced_context = M._enhance_completion_context(context)
    return original_resolve(enhanced_context)
  end

  logger.debug("Completion enhancements registered")
end

--- Setup navigation features
function M._setup_navigation_features()
  -- Enhanced go-to-definition with cross-project support
  local original_definition = vim.lsp.buf.definition
  
  vim.lsp.buf.definition = function()
    logger.debug("Enhanced go-to-definition triggered")
    
    -- Pre-cache related symbols for faster navigation
    M._precache_related_symbols()
    
    return original_definition()
  end

  -- Enhanced find references with solution-wide search
  local original_references = vim.lsp.buf.references
  
  vim.lsp.buf.references = function(context, options)
    logger.debug("Enhanced find references triggered")
    
    -- Enhance context for solution-wide search
    local enhanced_context = M._enhance_references_context(context)
    
    return original_references(enhanced_context, options)
  end

  -- Setup workspace symbol search enhancement
  local original_workspace_symbol = vim.lsp.buf.workspace_symbol
  
  vim.lsp.buf.workspace_symbol = function(query)
    logger.debug("Enhanced workspace symbol search", { query = query })
    
    -- Cache frequently accessed symbols
    M._cache_workspace_symbols(query)
    
    return original_workspace_symbol(query)
  end

  logger.debug("Navigation enhancements registered")
end

--- Setup symbol search features
function M._setup_symbol_search()
  -- Create custom symbol search command
  vim.api.nvim_create_user_command('DotnetSymbolSearch', function(opts)
    M.search_symbols(opts.args, opts.bang)
  end, {
    nargs = '?',
    bang = true,
    desc = 'Search symbols in solution (! for exact match)'
  })

  -- Create go-to-symbol command
  vim.api.nvim_create_user_command('DotnetGoToSymbol', function()
    M.go_to_symbol()
  end, {
    desc = 'Interactive symbol navigation'
  })

  logger.debug("Symbol search features registered")
end

--- Setup diagnostic enhancements
function M._setup_diagnostic_enhancements()
  -- Enhanced diagnostic display with solution context
  vim.diagnostic.config({
    virtual_text = {
      source = "always",
      format = function(diagnostic)
        return M._format_diagnostic_with_context(diagnostic)
      end
    },
    float = {
      source = "always",
      format = function(diagnostic)
        return M._format_diagnostic_with_context(diagnostic)
      end
    }
  })

  logger.debug("Diagnostic enhancements registered")
end

--- Enhance completion context with solution information
--- @param context table|nil Completion context
--- @return table enhanced_context Enhanced context
function M._enhance_completion_context(context)
  context = context or {}
  
  -- Add solution context
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project_info = M._get_project_info_for_file(file_path)
  
  if project_info then
    context.project = {
      name = project_info.name,
      framework = project_info.target_framework,
      dependencies = project_info.package_references or {}
    }
  end
  
  return context
end

--- Enhance references context for solution-wide search
--- @param context table|nil References context
--- @return table enhanced_context Enhanced context
function M._enhance_references_context(context)
  context = context or {}
  
  -- Enable solution-wide search
  context.includeDeclaration = true
  
  -- Add workspace folders for comprehensive search
  local workspace_folders = vim.lsp.buf.list_workspace_folders()
  if #workspace_folders > 0 then
    context.workspaceFolders = workspace_folders
  end
  
  return context
end

--- Pre-cache related symbols for faster navigation
function M._precache_related_symbols()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  
  -- Get symbol under cursor
  local params = vim.lsp.util.make_position_params()
  
  -- Request related symbols asynchronously
  vim.lsp.buf_request_all(bufnr, 'textDocument/documentSymbol', params, function(results)
    if results then
      for client_id, result in pairs(results) do
        if result.result then
          M._cache_document_symbols(bufnr, result.result)
        end
      end
    end
  end)
end

--- Cache document symbols for faster access
--- @param bufnr number Buffer number
--- @param symbols table Document symbols
function M._cache_document_symbols(bufnr, symbols)
  if not symbol_cache[bufnr] then
    symbol_cache[bufnr] = {}
  end
  
  symbol_cache[bufnr] = {
    symbols = symbols,
    timestamp = vim.loop.hrtime()
  }
  
  logger.debug("Cached document symbols", { 
    buffer = bufnr, 
    count = #symbols 
  })
end

--- Cache workspace symbols for faster search
--- @param query string Search query
function M._cache_workspace_symbols(query)
  if not query or query == "" then
    return
  end
  
  -- Check if already cached
  if completion_cache[query] then
    local cache_age = vim.loop.hrtime() - completion_cache[query].timestamp
    if cache_age < 30000000000 then -- 30 seconds in nanoseconds
      return -- Use cached result
    end
  end
  
  -- Request workspace symbols
  vim.lsp.buf_request_all(0, 'workspace/symbol', { query = query }, function(results)
    if results then
      local all_symbols = {}
      for client_id, result in pairs(results) do
        if result.result then
          vim.list_extend(all_symbols, result.result)
        end
      end
      
      completion_cache[query] = {
        symbols = all_symbols,
        timestamp = vim.loop.hrtime()
      }
      
      logger.debug("Cached workspace symbols", { 
        query = query, 
        count = #all_symbols 
      })
    end
  end)
end

--- Search symbols in solution
--- @param query string|nil Search query
--- @param exact_match boolean Whether to use exact matching
function M.search_symbols(query, exact_match)
  if not query or query == "" then
    -- Interactive symbol search
    vim.ui.input({ prompt = 'Symbol search: ' }, function(input)
      if input and input ~= "" then
        M.search_symbols(input, exact_match)
      end
    end)
    return
  end
  
  logger.info("Searching symbols", { query = query, exact = exact_match })
  
  -- Use cached results if available
  if completion_cache[query] then
    local cache_age = vim.loop.hrtime() - completion_cache[query].timestamp
    if cache_age < 30000000000 then -- 30 seconds
      M._display_symbol_results(completion_cache[query].symbols, query)
      return
    end
  end
  
  -- Perform workspace symbol search
  vim.lsp.buf_request_all(0, 'workspace/symbol', { query = query }, function(results)
    if not results then
      vim.notify("No symbols found for: " .. query, vim.log.levels.INFO)
      return
    end
    
    local all_symbols = {}
    for client_id, result in pairs(results) do
      if result.result then
        vim.list_extend(all_symbols, result.result)
      end
    end
    
    if exact_match then
      all_symbols = vim.tbl_filter(function(symbol)
        return symbol.name == query
      end, all_symbols)
    end
    
    M._display_symbol_results(all_symbols, query)
  end)
end

--- Display symbol search results
--- @param symbols table Symbol results
--- @param query string Search query
function M._display_symbol_results(symbols, query)
  if #symbols == 0 then
    vim.notify("No symbols found for: " .. query, vim.log.levels.INFO)
    return
  end
  
  if #symbols == 1 then
    -- Jump directly to single result
    local symbol = symbols[1]
    if symbol.location then
      vim.lsp.util.jump_to_location(symbol.location, 'utf-8')
    end
    return
  end
  
  -- Multiple results - show in quickfix
  local qf_items = {}
  for _, symbol in ipairs(symbols) do
    if symbol.location then
      local item = {
        filename = vim.uri_to_fname(symbol.location.uri),
        lnum = symbol.location.range.start.line + 1,
        col = symbol.location.range.start.character + 1,
        text = symbol.name .. " (" .. (symbol.kind or "unknown") .. ")"
      }
      table.insert(qf_items, item)
    end
  end
  
  vim.fn.setqflist(qf_items)
  vim.cmd('copen')
  
  logger.info("Displayed symbol search results", { 
    query = query, 
    count = #symbols 
  })
end

--- Interactive go-to-symbol
function M.go_to_symbol()
  -- Get document symbols for current buffer
  local bufnr = vim.api.nvim_get_current_buf()
  
  vim.lsp.buf_request(bufnr, 'textDocument/documentSymbol', 
    vim.lsp.util.make_position_params(), function(err, result)
    if err or not result then
      vim.notify("No symbols found in current document", vim.log.levels.INFO)
      return
    end
    
    -- Flatten nested symbols
    local flat_symbols = M._flatten_symbols(result)
    
    -- Create selection items
    local items = {}
    for _, symbol in ipairs(flat_symbols) do
      table.insert(items, {
        text = symbol.name .. " (" .. (symbol.kind or "unknown") .. ")",
        symbol = symbol
      })
    end
    
    -- Show selection UI
    vim.ui.select(items, {
      prompt = 'Go to symbol:',
      format_item = function(item) return item.text end
    }, function(choice)
      if choice and choice.symbol then
        local range = choice.symbol.range or choice.symbol.location.range
        vim.api.nvim_win_set_cursor(0, { range.start.line + 1, range.start.character })
      end
    end)
  end)
end

--- Flatten nested document symbols
--- @param symbols table Document symbols
--- @param prefix string|nil Prefix for nested symbols
--- @return table flat_symbols Flattened symbol list
function M._flatten_symbols(symbols, prefix)
  prefix = prefix or ""
  local flat = {}
  
  for _, symbol in ipairs(symbols) do
    local name = prefix .. symbol.name
    table.insert(flat, {
      name = name,
      kind = symbol.kind,
      range = symbol.range or symbol.location.range
    })
    
    -- Recursively flatten children
    if symbol.children then
      local children = M._flatten_symbols(symbol.children, name .. ".")
      vim.list_extend(flat, children)
    end
  end
  
  return flat
end

--- Format diagnostic with solution context
--- @param diagnostic table Diagnostic information
--- @return string formatted_diagnostic Formatted diagnostic message
function M._format_diagnostic_with_context(diagnostic)
  local message = diagnostic.message
  
  -- Add project context if available
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project_info = M._get_project_info_for_file(file_path)
  
  if project_info and project_info.name then
    message = message .. " [" .. project_info.name .. "]"
  end
  
  return message
end

--- Get project information for a file
--- @param file_path string File path
--- @return table|nil project_info Project information
function M._get_project_info_for_file(file_path)
  -- This would use the same logic as in handlers.lua
  -- For now, return nil to avoid duplication
  return nil
end

--- Handle completion done event
function M._on_completion_done()
  -- Update completion statistics
  logger.debug("Completion done")
end

--- Get IntelliSense status
--- @return table status IntelliSense status information
function M.get_status()
  return {
    initialized = intellisense_initialized,
    cached_symbols = vim.tbl_count(symbol_cache),
    cached_completions = vim.tbl_count(completion_cache)
  }
end

--- Shutdown IntelliSense features
function M.shutdown()
  if intellisense_initialized then
    logger.info("Shutting down IntelliSense features")
    
    -- Remove custom commands
    pcall(vim.api.nvim_del_user_command, 'DotnetSymbolSearch')
    pcall(vim.api.nvim_del_user_command, 'DotnetGoToSymbol')
    
    -- Clear caches
    completion_cache = {}
    symbol_cache = {}
    
    intellisense_initialized = false
    
    logger.info("IntelliSense features shutdown complete")
  end
end

return M
