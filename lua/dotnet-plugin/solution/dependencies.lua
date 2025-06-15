-- Dependency tracking for dotnet-plugin.nvim
-- Tracks project-to-project and package dependencies

local M = {}

local logger = require('dotnet-plugin.core.logger')

--- Dependency graph
--- @class DependencyGraph
--- @field projects table<string, ProjectNode> Project nodes by ID
--- @field packages table<string, PackageNode> Package nodes by name
--- @field edges table<string, string[]> Dependency edges

--- Project node in dependency graph
--- @class ProjectNode
--- @field id string Project ID
--- @field name string Project name
--- @field path string Project file path
--- @field type string Project type
--- @field framework string Target framework
--- @field dependencies string[] List of dependency IDs

--- Package node in dependency graph
--- @class PackageNode
--- @field name string Package name
--- @field version string Package version
--- @field dependents string[] List of dependent project IDs

--- Create a new dependency graph
--- @return DependencyGraph New dependency graph
function M.create_graph()
  return {
    projects = {},
    packages = {},
    edges = {}
  }
end

--- Add a project to the dependency graph
--- @param graph DependencyGraph Dependency graph
--- @param project ProjectInfo Project information
function M.add_project(graph, project)
  local project_id = M.get_project_id(project.path)
  
  graph.projects[project_id] = {
    id = project_id,
    name = project.name,
    path = project.path,
    type = project.type,
    framework = project.framework,
    dependencies = {}
  }
  
  graph.edges[project_id] = {}
  
  logger.debug("Added project to dependency graph", {
    id = project_id,
    name = project.name
  })
end

--- Add project dependencies to the graph
--- @param graph DependencyGraph Dependency graph
--- @param project ProjectInfo Project information
function M.add_project_dependencies(graph, project)
  local project_id = M.get_project_id(project.path)
  local project_node = graph.projects[project_id]
  
  if not project_node then
    logger.warn("Project not found in graph", { id = project_id })
    return
  end
  
  -- Add project references
  for _, ref in ipairs(project.project_references) do
    local ref_id = M.get_project_id(ref.path)
    
    -- Add edge
    table.insert(graph.edges[project_id], ref_id)
    table.insert(project_node.dependencies, ref_id)
    
    logger.debug("Added project dependency", {
      from = project_id,
      to = ref_id
    })
  end
  
  -- Add package references
  for _, pkg in ipairs(project.package_references) do
    local package_key = pkg.name .. "@" .. pkg.version
    
    -- Create package node if it doesn't exist
    if not graph.packages[package_key] then
      graph.packages[package_key] = {
        name = pkg.name,
        version = pkg.version,
        dependents = {}
      }
    end
    
    -- Add project as dependent
    table.insert(graph.packages[package_key].dependents, project_id)
    
    logger.debug("Added package dependency", {
      project = project_id,
      package = package_key
    })
  end
end

--- Get project ID from path
--- @param project_path string Project file path
--- @return string Project ID
function M.get_project_id(project_path)
  return vim.fn.fnamemodify(project_path, ":t:r")
end

--- Get project dependencies (direct)
--- @param graph DependencyGraph Dependency graph
--- @param project_id string Project ID
--- @return string[] List of dependency IDs
function M.get_dependencies(graph, project_id)
  return graph.edges[project_id] or {}
end

--- Get project dependents (projects that depend on this one)
--- @param graph DependencyGraph Dependency graph
--- @param project_id string Project ID
--- @return string[] List of dependent project IDs
function M.get_dependents(graph, project_id)
  local dependents = {}
  
  for id, deps in pairs(graph.edges) do
    if vim.tbl_contains(deps, project_id) then
      table.insert(dependents, id)
    end
  end
  
  return dependents
end

--- Get all dependencies (transitive)
--- @param graph DependencyGraph Dependency graph
--- @param project_id string Project ID
--- @return string[] List of all dependency IDs
function M.get_all_dependencies(graph, project_id)
  local visited = {}
  local dependencies = {}
  
  local function visit(id)
    if visited[id] then
      return
    end
    
    visited[id] = true
    local deps = graph.edges[id] or {}
    
    for _, dep_id in ipairs(deps) do
      table.insert(dependencies, dep_id)
      visit(dep_id)
    end
  end
  
  visit(project_id)
  return dependencies
end

--- Check for circular dependencies
--- @param graph DependencyGraph Dependency graph
--- @return boolean, string[] Has cycles, list of cycles
function M.check_circular_dependencies(graph)
  local visited = {}
  local rec_stack = {}
  local cycles = {}
  
  local function has_cycle(node, path)
    if rec_stack[node] then
      -- Found a cycle
      local cycle_start = nil
      for i, n in ipairs(path) do
        if n == node then
          cycle_start = i
          break
        end
      end
      
      if cycle_start then
        local cycle = {}
        for i = cycle_start, #path do
          table.insert(cycle, path[i])
        end
        table.insert(cycle, node) -- Complete the cycle
        table.insert(cycles, cycle)
      end
      
      return true
    end
    
    if visited[node] then
      return false
    end
    
    visited[node] = true
    rec_stack[node] = true
    table.insert(path, node)
    
    local deps = graph.edges[node] or {}
    for _, dep in ipairs(deps) do
      if has_cycle(dep, path) then
        return true
      end
    end
    
    rec_stack[node] = false
    table.remove(path)
    return false
  end
  
  for project_id, _ in pairs(graph.projects) do
    if not visited[project_id] then
      has_cycle(project_id, {})
    end
  end
  
  return #cycles > 0, cycles
end

--- Get topological sort of projects
--- @param graph DependencyGraph Dependency graph
--- @return string[]|nil Sorted project IDs or nil if cycles exist
function M.topological_sort(graph)
  local has_cycles, cycles = M.check_circular_dependencies(graph)
  if has_cycles then
    logger.error("Circular dependencies detected", { cycles = cycles })
    return nil
  end
  
  local in_degree = {}
  local queue = {}
  local result = {}
  
  -- Calculate in-degrees
  for project_id, _ in pairs(graph.projects) do
    in_degree[project_id] = 0
  end
  
  for _, deps in pairs(graph.edges) do
    for _, dep_id in ipairs(deps) do
      if in_degree[dep_id] then
        in_degree[dep_id] = in_degree[dep_id] + 1
      end
    end
  end
  
  -- Find nodes with no incoming edges
  for project_id, degree in pairs(in_degree) do
    if degree == 0 then
      table.insert(queue, project_id)
    end
  end
  
  -- Process queue
  while #queue > 0 do
    local current = table.remove(queue, 1)
    table.insert(result, current)
    
    local deps = graph.edges[current] or {}
    for _, dep_id in ipairs(deps) do
      if in_degree[dep_id] then
        in_degree[dep_id] = in_degree[dep_id] - 1
        if in_degree[dep_id] == 0 then
          table.insert(queue, dep_id)
        end
      end
    end
  end
  
  return result
end

--- Get build order for projects
--- @param graph DependencyGraph Dependency graph
--- @return string[]|nil Build order or nil if cycles exist
function M.get_build_order(graph)
  local sorted = M.topological_sort(graph)
  if not sorted then
    return nil
  end
  
  -- Reverse the order (dependencies first)
  local build_order = {}
  for i = #sorted, 1, -1 do
    table.insert(build_order, sorted[i])
  end
  
  return build_order
end

--- Get package usage statistics
--- @param graph DependencyGraph Dependency graph
--- @return table Package usage statistics
function M.get_package_stats(graph)
  local stats = {}
  
  for package_key, package_node in pairs(graph.packages) do
    stats[package_key] = {
      name = package_node.name,
      version = package_node.version,
      usage_count = #package_node.dependents,
      dependents = package_node.dependents
    }
  end
  
  return stats
end

--- Find projects that can be built in parallel
--- @param graph DependencyGraph Dependency graph
--- @return table[] Groups of projects that can be built in parallel
function M.get_parallel_build_groups(graph)
  local build_order = M.get_build_order(graph)
  if not build_order then
    return {}
  end
  
  local groups = {}
  local processed = {}
  
  for _, project_id in ipairs(build_order) do
    if not processed[project_id] then
      local group = { project_id }
      processed[project_id] = true
      
      -- Find other projects that can be built at the same time
      for _, other_id in ipairs(build_order) do
        if not processed[other_id] then
          local can_parallel = true
          
          -- Check if other_id depends on any project in current group
          local other_deps = M.get_all_dependencies(graph, other_id)
          for _, group_project in ipairs(group) do
            if vim.tbl_contains(other_deps, group_project) then
              can_parallel = false
              break
            end
          end
          
          if can_parallel then
            table.insert(group, other_id)
            processed[other_id] = true
          end
        end
      end
      
      table.insert(groups, group)
    end
  end
  
  return groups
end

return M
