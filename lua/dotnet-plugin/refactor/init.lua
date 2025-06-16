-- dotnet-plugin.nvim - Refactoring Module
-- Provides advanced refactoring and code generation capabilities for .NET

local M = {}

-- Import dependencies
local config = require('dotnet-plugin.core.config')
local logger = require('dotnet-plugin.core.logger')
local events = require('dotnet-plugin.core.events')

-- Refactoring state
M._initialized = false
M._active_refactorings = {}

-- Refactoring types
M.REFACTORING_TYPES = {
  RENAME_SYMBOL = "rename_symbol",
  EXTRACT_METHOD = "extract_method",
  EXTRACT_INTERFACE = "extract_interface",
  MOVE_TYPE = "move_type",
  ORGANIZE_USINGS = "organize_usings",
  ADD_USING = "add_using",
  REMOVE_UNUSED_USINGS = "remove_unused_usings",
  GENERATE_CONSTRUCTOR = "generate_constructor",
  GENERATE_PROPERTIES = "generate_properties",
  IMPLEMENT_INTERFACE = "implement_interface"
}

--- Setup refactoring integration
--- @param opts table|nil Configuration options
--- @return boolean success True if setup succeeded
function M.setup(opts)
  if M._initialized then
    return true
  end

  opts = opts or {}
  
  -- Register refactoring commands
  M._register_commands()

  -- Setup event handlers
  M._setup_event_handlers()

  M._initialized = true
  logger.info("Refactoring integration initialized")
  
  return true
end

--- Register refactoring commands
function M._register_commands()
  -- Rename symbol command
  vim.api.nvim_create_user_command('DotnetRename', function(opts)
    M.rename_symbol(opts.args)
  end, {
    nargs = '?',
    desc = 'Rename symbol at cursor'
  })
  
  -- Extract method command
  vim.api.nvim_create_user_command('DotnetExtractMethod', function(opts)
    M.extract_method(opts.args)
  end, {
    nargs = '?',
    range = true,
    desc = 'Extract selected code into method'
  })
  
  -- Organize usings command
  vim.api.nvim_create_user_command('DotnetOrganizeUsings', function()
    M.organize_usings()
  end, {
    desc = 'Organize using statements'
  })
  
  -- Add using command
  vim.api.nvim_create_user_command('DotnetAddUsing', function(opts)
    M.add_using(opts.args)
  end, {
    nargs = 1,
    desc = 'Add using statement'
  })
  
  -- Remove unused usings command
  vim.api.nvim_create_user_command('DotnetRemoveUnusedUsings', function()
    M.remove_unused_usings()
  end, {
    desc = 'Remove unused using statements'
  })
  
  -- Generate constructor command
  vim.api.nvim_create_user_command('DotnetGenerateConstructor', function()
    M.generate_constructor()
  end, {
    desc = 'Generate constructor for current class'
  })
  
  -- Generate properties command
  vim.api.nvim_create_user_command('DotnetGenerateProperties', function()
    M.generate_properties()
  end, {
    desc = 'Generate properties for fields'
  })
  
  -- Implement interface command
  vim.api.nvim_create_user_command('DotnetImplementInterface', function(opts)
    M.implement_interface(opts.args)
  end, {
    nargs = '?',
    desc = 'Implement interface members'
  })
  
  logger.debug("Refactoring commands registered")
end

--- Setup event handlers
function M._setup_event_handlers()
  -- Listen for LSP events that might trigger refactoring opportunities
  events.subscribe("lsp_code_action", function(data)
    M._process_code_actions(data)
  end)
  
  logger.debug("Refactoring event handlers setup")
end

--- Rename symbol at cursor
--- @param new_name string|nil New name for symbol
function M.rename_symbol(new_name)
  local current_word = vim.fn.expand('<cword>')
  
  if not new_name or new_name == "" then
    new_name = vim.fn.input("Rename '" .. current_word .. "' to: ")
    if new_name == "" then
      return
    end
  end
  
  logger.info("Renaming symbol '" .. current_word .. "' to '" .. new_name .. "'")
  
  -- Use LSP rename if available
  local lsp_ok = pcall(vim.lsp.buf.rename, new_name)
  if lsp_ok then
    logger.debug("Using LSP rename")
    return
  end
  
  -- Fallback to manual rename
  M._manual_rename_symbol(current_word, new_name)
end

--- Manual symbol rename using find/replace
--- @param old_name string Old symbol name
--- @param new_name string New symbol name
function M._manual_rename_symbol(old_name, new_name)
  local current_file = vim.fn.expand('%:p')
  local project_file = M._find_project_file(current_file)
  
  if not project_file then
    logger.error("No project file found for refactoring")
    return
  end
  
  logger.warn("LSP rename not available, using find/replace fallback")
  
  local choice = vim.fn.confirm(
    "Rename all occurrences of '" .. old_name .. "' to '" .. new_name .. "' in project?",
    "&Yes\n&No", 2
  )
  
  if choice == 1 then
    M._find_and_replace_in_project(old_name, new_name, project_file)
  end
end

--- Extract method from selected code
--- @param method_name string|nil Name for extracted method
function M.extract_method(method_name)
  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  if start_pos[2] == 0 or end_pos[2] == 0 then
    logger.error("No selection found. Select code to extract first.")
    return
  end
  
  local selected_lines = vim.fn.getline(start_pos[2], end_pos[2])
  local selected_code = table.concat(selected_lines, "\n")
  
  if not method_name or method_name == "" then
    method_name = vim.fn.input("Method name: ")
    if method_name == "" then
      return
    end
  end
  
  logger.info("Extracting method: " .. method_name)
  
  -- Analyze selected code for variables and return type
  local analysis = M._analyze_code_for_extraction(selected_code, start_pos[2], end_pos[2])
  
  -- Generate method signature
  local method_signature = M._generate_method_signature(method_name, analysis)
  
  -- Generate method call
  local method_call = M._generate_method_call(method_name, analysis)
  
  -- Replace selected code with method call
  vim.fn.setline(start_pos[2], method_call)
  if end_pos[2] > start_pos[2] then
    vim.fn.deletebufline('%', start_pos[2] + 1, end_pos[2])
  end
  
  -- Insert method at appropriate location
  M._insert_method_in_class(method_signature, selected_code)
  
  logger.info("Method extracted successfully")
end

--- Analyze code for extraction
--- @param code string Selected code
--- @param start_line number Start line number
--- @param end_line number End line number
--- @return table analysis
function M._analyze_code_for_extraction(code, start_line, end_line)
  local analysis = {
    parameters = {},
    return_type = "void",
    return_variable = nil,
    local_variables = {}
  }
  
  -- Simple analysis (would be more sophisticated in real implementation)
  -- Look for variable declarations and usage
  for line in code:gmatch("[^\r\n]+") do
    -- Find variable declarations
    local var_type, var_name = line:match("(%w+)%s+(%w+)%s*=")
    if var_type and var_name then
      table.insert(analysis.local_variables, {type = var_type, name = var_name})
    end
    
    -- Look for return statements
    local return_value = line:match("return%s+([^;]+)")
    if return_value then
      analysis.return_type = "object" -- Simplified
      analysis.return_variable = return_value:trim and return_value:trim() or return_value
    end
  end
  
  return analysis
end

--- Generate method signature
--- @param method_name string Method name
--- @param analysis table Code analysis
--- @return string signature
function M._generate_method_signature(method_name, analysis)
  local params = {}
  for _, param in ipairs(analysis.parameters) do
    table.insert(params, param.type .. " " .. param.name)
  end
  
  local param_string = table.concat(params, ", ")
  return string.format("private %s %s(%s)", analysis.return_type, method_name, param_string)
end

--- Generate method call
--- @param method_name string Method name
--- @param analysis table Code analysis
--- @return string call
function M._generate_method_call(method_name, analysis)
  local args = {}
  for _, param in ipairs(analysis.parameters) do
    table.insert(args, param.name)
  end
  
  local arg_string = table.concat(args, ", ")
  local call = method_name .. "(" .. arg_string .. ")"
  
  if analysis.return_type ~= "void" then
    call = "var result = " .. call
  end
  
  return call .. ";"
end

--- Insert method in class
--- @param signature string Method signature
--- @param body string Method body
function M._insert_method_in_class(signature, body)
  -- Find appropriate location to insert method (simplified)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local insert_line = #lines - 1 -- Insert before last line (simplified)
  
  local method_lines = {
    "",
    "    " .. signature,
    "    {",
  }
  
  -- Add body lines with proper indentation
  for line in body:gmatch("[^\r\n]+") do
    table.insert(method_lines, "        " .. line)
  end
  
  table.insert(method_lines, "    }")
  
  vim.api.nvim_buf_set_lines(0, insert_line, insert_line, false, method_lines)
end

--- Organize using statements
function M.organize_usings()
  logger.info("Organizing using statements")
  
  -- Use LSP code action if available
  local lsp_ok = pcall(function()
    vim.lsp.buf.code_action({
      context = {
        only = {"source.organizeImports"}
      }
    })
  end)
  
  if lsp_ok then
    logger.debug("Using LSP organize imports")
    return
  end
  
  -- Fallback to manual organization
  M._manual_organize_usings()
end

--- Manual using organization
function M._manual_organize_usings()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local using_lines = {}
  local other_lines = {}
  local in_usings = true
  
  for i, line in ipairs(lines) do
    if line:match("^using%s+") then
      if in_usings then
        table.insert(using_lines, line)
      else
        -- Using statement found after other code, leave it alone
        table.insert(other_lines, line)
      end
    else
      if line:trim and line:trim() ~= "" and not line:match("^//") then
        in_usings = false
      elseif line ~= "" and not line:match("^//") then
        in_usings = false
      end
      table.insert(other_lines, line)
    end
  end
  
  -- Sort using statements
  table.sort(using_lines)
  
  -- Combine lines
  local organized_lines = {}
  for _, line in ipairs(using_lines) do
    table.insert(organized_lines, line)
  end
  
  if #using_lines > 0 and #other_lines > 0 then
    table.insert(organized_lines, "")
  end
  
  for _, line in ipairs(other_lines) do
    table.insert(organized_lines, line)
  end
  
  -- Replace buffer content
  vim.api.nvim_buf_set_lines(0, 0, -1, false, organized_lines)
  
  logger.info("Using statements organized")
end

--- Add using statement
--- @param namespace string Namespace to add
function M.add_using(namespace)
  if not namespace or namespace == "" then
    logger.error("Namespace required")
    return
  end
  
  logger.info("Adding using statement: " .. namespace)
  
  local using_statement = "using " .. namespace .. ";"
  
  -- Find where to insert the using statement
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local insert_line = 0
  
  -- Find last using statement
  for i, line in ipairs(lines) do
    if line:match("^using%s+") then
      insert_line = i
    elseif line:trim and line:trim() ~= "" and not line:match("^//") then
      break
    elseif line ~= "" and not line:match("^//") then
      break
    end
  end
  
  -- Check if using already exists
  for _, line in ipairs(lines) do
    if line == using_statement then
      logger.info("Using statement already exists")
      return
    end
  end
  
  -- Insert using statement
  vim.api.nvim_buf_set_lines(0, insert_line, insert_line, false, {using_statement})
  
  logger.info("Using statement added")
end

--- Remove unused using statements
function M.remove_unused_usings()
  logger.info("Removing unused using statements")
  
  -- Use LSP code action if available
  local lsp_ok = pcall(function()
    vim.lsp.buf.code_action({
      context = {
        only = {"source.removeUnusedImports"}
      }
    })
  end)
  
  if lsp_ok then
    logger.debug("Using LSP remove unused imports")
    return
  end
  
  logger.warn("LSP not available for removing unused usings")
end

--- Generate constructor for current class
function M.generate_constructor()
  logger.info("Generating constructor")
  
  -- Find class name and fields
  local class_info = M._analyze_current_class()
  if not class_info then
    logger.error("No class found at cursor")
    return
  end
  
  -- Generate constructor
  local constructor = M._generate_constructor_code(class_info)
  
  -- Insert constructor in class
  M._insert_constructor(constructor, class_info)
  
  logger.info("Constructor generated")
end

--- Analyze current class for constructor generation
--- @return table|nil class_info
function M._analyze_current_class()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local class_name = nil
  local fields = {}
  
  -- Find class declaration
  for _, line in ipairs(lines) do
    local name = line:match("class%s+(%w+)")
    if name then
      class_name = name
      break
    end
  end
  
  if not class_name then
    return nil
  end
  
  -- Find private fields
  for _, line in ipairs(lines) do
    local field_type, field_name = line:match("private%s+(%w+)%s+([_%w]+)")
    if field_type and field_name then
      table.insert(fields, {type = field_type, name = field_name})
    end
  end
  
  return {
    name = class_name,
    fields = fields
  }
end

--- Generate constructor code
--- @param class_info table Class information
--- @return table constructor_lines
function M._generate_constructor_code(class_info)
  local lines = {}
  
  -- Constructor signature
  local params = {}
  for _, field in ipairs(class_info.fields) do
    table.insert(params, field.type .. " " .. field.name:gsub("^_", ""))
  end
  
  local signature = "public " .. class_info.name .. "(" .. table.concat(params, ", ") .. ")"
  table.insert(lines, signature)
  table.insert(lines, "{")
  
  -- Constructor body
  for _, field in ipairs(class_info.fields) do
    local param_name = field.name:gsub("^_", "")
    table.insert(lines, "    " .. field.name .. " = " .. param_name .. ";")
  end
  
  table.insert(lines, "}")
  
  return lines
end

--- Insert constructor in class
--- @param constructor table Constructor lines
--- @param class_info table Class information
function M._insert_constructor(constructor, class_info)
  -- Find appropriate location (after fields, before methods)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local insert_line = #lines - 1 -- Simplified
  
  -- Add empty line before constructor
  table.insert(constructor, 1, "")
  
  vim.api.nvim_buf_set_lines(0, insert_line, insert_line, false, constructor)
end

--- Generate properties for fields
function M.generate_properties()
  logger.info("Generating properties")
  
  local class_info = M._analyze_current_class()
  if not class_info then
    logger.error("No class found at cursor")
    return
  end
  
  -- Generate properties for each field
  local properties = {}
  for _, field in ipairs(class_info.fields) do
    local prop_lines = M._generate_property_code(field)
    for _, line in ipairs(prop_lines) do
      table.insert(properties, line)
    end
    table.insert(properties, "")
  end
  
  -- Insert properties
  if #properties > 0 then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local insert_line = #lines - 1
    
    vim.api.nvim_buf_set_lines(0, insert_line, insert_line, false, properties)
    logger.info("Properties generated")
  end
end

--- Generate property code for a field
--- @param field table Field information
--- @return table property_lines
function M._generate_property_code(field)
  local prop_name = field.name:gsub("^_", ""):gsub("^%l", string.upper)
  
  return {
    "public " .. field.type .. " " .. prop_name,
    "{",
    "    get { return " .. field.name .. "; }",
    "    set { " .. field.name .. " = value; }",
    "}"
  }
end

--- Implement interface members
--- @param interface_name string|nil Interface name
function M.implement_interface(interface_name)
  if not interface_name or interface_name == "" then
    interface_name = vim.fn.input("Interface name: ")
    if interface_name == "" then
      return
    end
  end
  
  logger.info("Implementing interface: " .. interface_name)
  
  -- Use LSP code action if available
  local lsp_ok = pcall(function()
    vim.lsp.buf.code_action({
      context = {
        only = {"quickfix.implement.interface"}
      }
    })
  end)
  
  if lsp_ok then
    logger.debug("Using LSP implement interface")
    return
  end
  
  logger.warn("LSP not available for interface implementation")
end

--- Find project file for current buffer
--- @param file_path string Current file path
--- @return string|nil project_file
function M._find_project_file(file_path)
  local dir = vim.fn.fnamemodify(file_path, ':h')
  
  while dir ~= '/' and dir ~= '' do
    local project_files = vim.fn.glob(dir .. '/*.{csproj,fsproj,vbproj}', false, true)
    if #project_files > 0 then
      return project_files[1]
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  
  return nil
end

--- Find and replace in project
--- @param old_text string Text to replace
--- @param new_text string Replacement text
--- @param project_file string Project file path
function M._find_and_replace_in_project(old_text, new_text, project_file)
  local project_dir = vim.fn.fnamemodify(project_file, ':h')
  
  -- Find all C# files in project
  local cs_files = vim.fn.glob(project_dir .. '/**/*.cs', false, true)
  
  local replaced_count = 0
  for _, file in ipairs(cs_files) do
    local content = table.concat(vim.fn.readfile(file), '\n')
    local new_content = content:gsub(old_text, new_text)
    
    if new_content ~= content then
      vim.fn.writefile(vim.split(new_content, '\n'), file)
      replaced_count = replaced_count + 1
    end
  end
  
  logger.info("Replaced '" .. old_text .. "' with '" .. new_text .. "' in " .. replaced_count .. " files")
end

--- Process code actions from LSP
--- @param data table Code action data
function M._process_code_actions(data)
  -- Process available code actions and suggest refactorings
  logger.debug("Processing code actions: " .. vim.inspect(data))
end

--- Shutdown refactoring integration
function M.shutdown()
  if M._initialized then
    -- Cancel active refactorings
    for _, refactoring in pairs(M._active_refactorings) do
      if refactoring.cancel then
        refactoring:cancel()
      end
    end
    
    M._active_refactorings = {}
    M._initialized = false
    
    logger.info("Refactoring integration shutdown")
  end
end

return M
