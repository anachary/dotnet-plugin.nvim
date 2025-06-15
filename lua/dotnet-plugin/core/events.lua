-- Event system for dotnet-plugin.nvim
-- Implements a publish-subscribe pattern for plugin communication

local M = {}

-- Event definitions
M.EVENTS = {
  -- Solution events
  SOLUTION_LOADING = "dotnet_plugin_solution_loading",
  SOLUTION_LOADED = "dotnet_plugin_solution_loaded",
  SOLUTION_UNLOADED = "dotnet_plugin_solution_unloaded",
  SOLUTION_ERROR = "dotnet_plugin_solution_error",

  -- Project events
  PROJECT_LOADING = "dotnet_plugin_project_loading",
  PROJECT_LOADED = "dotnet_plugin_project_loaded",
  PROJECT_UNLOADED = "dotnet_plugin_project_unloaded",
  PROJECT_CHANGED = "dotnet_plugin_project_changed",
  PROJECT_ERROR = "dotnet_plugin_project_error",

  -- Build events
  BUILD_STARTED = "dotnet_plugin_build_started",
  BUILD_PROGRESS = "dotnet_plugin_build_progress",
  BUILD_COMPLETED = "dotnet_plugin_build_completed",
  BUILD_FAILED = "dotnet_plugin_build_failed",

  -- File events
  FILE_CREATED = "dotnet_plugin_file_created",
  FILE_MODIFIED = "dotnet_plugin_file_modified",
  FILE_DELETED = "dotnet_plugin_file_deleted",

  -- Buffer events
  BUFFER_OPENED = "dotnet_plugin_buffer_opened",
  BUFFER_CLOSED = "dotnet_plugin_buffer_closed",
  BUFFER_SAVED = "dotnet_plugin_buffer_saved",

  -- Process events
  PROCESS_STARTED = "dotnet_plugin_process_started",
  PROCESS_COMPLETED = "dotnet_plugin_process_completed",
  PROCESS_FAILED = "dotnet_plugin_process_failed",

  -- File watcher events
  SOLUTION_RELOAD_REQUESTED = "dotnet_plugin_solution_reload_requested",
  PROJECT_RELOAD_REQUESTED = "dotnet_plugin_project_reload_requested",
  DEPENDENCY_ANALYSIS_REQUESTED = "dotnet_plugin_dependency_analysis_requested",

  -- LSP events
  LSP_ATTACHED = "dotnet_plugin_lsp_attached",
  LSP_DETACHED = "dotnet_plugin_lsp_detached",
  LSP_ERROR = "dotnet_plugin_lsp_error",
  LSP_INSTALLATION_STARTED = "dotnet_plugin_lsp_installation_started",
  LSP_INSTALLATION_COMPLETED = "dotnet_plugin_lsp_installation_completed",
  LSP_INSTALLATION_FAILED = "dotnet_plugin_lsp_installation_failed",

  -- Code events
  CODE_MODIFIED = "dotnet_plugin_code_modified"
}

-- Event listeners storage
local listeners = {}

-- Event queue for async processing
local event_queue = {}

-- Processing state
local processing = false

--- Setup the event system
function M.setup()
  -- Initialize listeners table
  for _, event_name in pairs(M.EVENTS) do
    listeners[event_name] = {}
  end
  
  -- Setup Neovim autocommands for buffer events
  local augroup = vim.api.nvim_create_augroup("DotnetPluginEvents", { clear = true })
  
  vim.api.nvim_create_autocmd("BufRead", {
    group = augroup,
    pattern = "*.cs,*.fs,*.vb,*.csproj,*.fsproj,*.vbproj,*.sln",
    callback = function(args)
      M.emit(M.EVENTS.BUFFER_OPENED, {
        buffer = args.buf,
        file = args.file,
        filetype = vim.bo[args.buf].filetype
      })
    end
  })
  
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    pattern = "*.cs,*.fs,*.vb,*.csproj,*.fsproj,*.vbproj,*.sln",
    callback = function(args)
      M.emit(M.EVENTS.BUFFER_CLOSED, {
        buffer = args.buf,
        file = args.file
      })
    end
  })
  
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*.cs,*.fs,*.vb,*.csproj,*.fsproj,*.vbproj,*.sln",
    callback = function(args)
      M.emit(M.EVENTS.BUFFER_SAVED, {
        buffer = args.buf,
        file = args.file,
        filetype = vim.bo[args.buf].filetype
      })
    end
  })
end

--- Subscribe to an event
--- @param event_name string Event name
--- @param callback function Callback function
--- @param opts table|nil Options (priority, once)
--- @return number Listener ID for unsubscribing
function M.subscribe(event_name, callback, opts)
  opts = opts or {}
  
  if not listeners[event_name] then
    error(string.format("Unknown event: %s", event_name))
  end
  
  local listener = {
    id = #listeners[event_name] + 1,
    callback = callback,
    priority = opts.priority or 0,
    once = opts.once or false
  }
  
  table.insert(listeners[event_name], listener)
  
  -- Sort by priority (higher priority first)
  table.sort(listeners[event_name], function(a, b)
    return a.priority > b.priority
  end)
  
  return listener.id
end

--- Unsubscribe from an event
--- @param event_name string Event name
--- @param listener_id number Listener ID
function M.unsubscribe(event_name, listener_id)
  if not listeners[event_name] then
    return
  end
  
  for i, listener in ipairs(listeners[event_name]) do
    if listener.id == listener_id then
      table.remove(listeners[event_name], i)
      break
    end
  end
end

--- Emit an event
--- @param event_name string Event name
--- @param data any Event data
function M.emit(event_name, data)
  if not listeners[event_name] then
    return
  end
  
  -- Add to event queue for async processing
  table.insert(event_queue, {
    event_name = event_name,
    data = data,
    timestamp = vim.loop.hrtime()
  })
  
  -- Process queue if not already processing
  if not processing then
    vim.schedule(M.process_queue)
  end
end

--- Process the event queue
function M.process_queue()
  if processing then
    return
  end
  
  processing = true
  
  while #event_queue > 0 do
    local event = table.remove(event_queue, 1)
    local event_listeners = listeners[event.event_name] or {}
    
    -- Process listeners
    local to_remove = {}
    for i, listener in ipairs(event_listeners) do
      local success, result = pcall(listener.callback, event.data)
      
      if not success then
        vim.notify(
          string.format("Error in event listener for %s: %s", event.event_name, result),
          vim.log.levels.ERROR
        )
      end
      
      -- Mark for removal if it's a one-time listener
      if listener.once then
        table.insert(to_remove, i)
      end
    end
    
    -- Remove one-time listeners (in reverse order to maintain indices)
    for i = #to_remove, 1, -1 do
      table.remove(event_listeners, to_remove[i])
    end
  end
  
  processing = false
end

--- Get all listeners for an event
--- @param event_name string Event name
--- @return table List of listeners
function M.get_listeners(event_name)
  return listeners[event_name] or {}
end

--- Clear all listeners for an event
--- @param event_name string Event name
function M.clear_listeners(event_name)
  if listeners[event_name] then
    listeners[event_name] = {}
  end
end

--- Get event queue size
--- @return number Queue size
function M.get_queue_size()
  return #event_queue
end

return M
