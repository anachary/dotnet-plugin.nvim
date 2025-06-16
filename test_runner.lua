#!/usr/bin/env lua

-- Simple test runner for Phase 2.1 components
-- This validates the basic structure and functionality

local function test_module_loading()
  print("Testing module loading...")
  
  -- Add current directory to package path
  package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
  
  local success = true
  local modules = {
    "dotnet-plugin.core.config",
    "dotnet-plugin.core.logger", 
    "dotnet-plugin.core.events",
    "dotnet-plugin.debug",
    "dotnet-plugin.test",
    "dotnet-plugin.refactor"
  }
  
  for _, module_name in ipairs(modules) do
    local ok, module = pcall(require, module_name)
    if ok then
      print("✓ " .. module_name .. " loaded successfully")
    else
      print("✗ " .. module_name .. " failed to load: " .. tostring(module))
      success = false
    end
  end
  
  return success
end

local function test_configuration()
  print("\nTesting configuration...")
  
  local config = require('dotnet-plugin.core.config')
  
  -- Test setup with Phase 2.1 config
  local test_config = {
    debug = { enabled = true },
    test = { enabled = true },
    refactor = { enabled = true }
  }
  
  local ok, err = pcall(config.setup, test_config)
  if ok then
    print("✓ Configuration setup successful")
    
    -- Test getting values
    local debug_enabled = config.get_value("debug.enabled")
    local test_enabled = config.get_value("test.enabled")
    local refactor_enabled = config.get_value("refactor.enabled")
    
    if debug_enabled and test_enabled and refactor_enabled then
      print("✓ Configuration values accessible")
      return true
    else
      print("✗ Configuration values not accessible")
      return false
    end
  else
    print("✗ Configuration setup failed: " .. tostring(err))
    return false
  end
end

local function test_component_initialization()
  print("\nTesting component initialization...")
  
  local config = require('dotnet-plugin.core.config')
  local logger = require('dotnet-plugin.core.logger')
  
  -- Setup minimal config
  config.setup({
    logging = { level = "info", file_enabled = false, buffer_enabled = false },
    debug = { enabled = true },
    test = { enabled = true },
    refactor = { enabled = true }
  })
  
  -- Mock vim functions for testing
  _G.vim = _G.vim or {}
  _G.vim.api = _G.vim.api or {}
  _G.vim.fn = _G.vim.fn or {}
  _G.vim.loop = _G.vim.loop or {}
  _G.vim.log = _G.vim.log or {}
  _G.vim.schedule = _G.vim.schedule or function(fn) fn() end
  
  -- Mock API functions
  _G.vim.api.nvim_create_user_command = function() end
  _G.vim.api.nvim_create_augroup = function() return 1 end
  _G.vim.api.nvim_create_autocmd = function() end
  _G.vim.keymap = { set = function() end }
  _G.vim.log.levels = { WARN = 1, ERROR = 2 }
  _G.vim.notify = function() end
  
  logger.setup(config.get().logging)
  
  local success = true
  
  -- Test debug module
  local debug = require('dotnet-plugin.debug')
  local debug_ok, debug_err = pcall(debug.setup)
  if debug_ok then
    print("✓ Debug module initialized")
  else
    print("✗ Debug module failed: " .. tostring(debug_err))
    success = false
  end
  
  -- Test test module
  local test = require('dotnet-plugin.test')
  local test_ok, test_err = pcall(test.setup)
  if test_ok then
    print("✓ Test module initialized")
  else
    print("✗ Test module failed: " .. tostring(test_err))
    success = false
  end
  
  -- Test refactor module
  local refactor = require('dotnet-plugin.refactor')
  local refactor_ok, refactor_err = pcall(refactor.setup)
  if refactor_ok then
    print("✓ Refactor module initialized")
  else
    print("✗ Refactor module failed: " .. tostring(refactor_err))
    success = false
  end
  
  return success
end

local function test_main_plugin()
  print("\nTesting main plugin integration...")
  
  -- Mock additional vim functions
  _G.vim.fn.executable = function() return 1 end
  _G.vim.fn.expand = function() return "" end
  _G.vim.fn.getcwd = function() return "/tmp" end
  _G.vim.fn.glob = function() return {} end
  _G.vim.fn.tempname = function() return "/tmp/test" end
  _G.vim.fn.mkdir = function() end
  _G.vim.fn.writefile = function() end
  _G.vim.fn.readfile = function() return {} end
  _G.vim.fn.filereadable = function() return 0 end
  _G.vim.fn.fnamemodify = function(path, mod) return path end
  _G.vim.tbl_isempty = function(t) return next(t) == nil end
  _G.vim.split = function(str, sep) 
    local result = {}
    for part in str:gmatch("[^" .. sep .. "]+") do
      table.insert(result, part)
    end
    return result
  end
  _G.vim.deepcopy = function(t) 
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = vim.deepcopy(v)
    end
    return copy
  end
  
  local main_plugin = require('dotnet-plugin')
  
  local ok, err = pcall(main_plugin.setup, {
    debug = { enabled = true },
    test = { enabled = true },
    refactor = { enabled = true }
  })
  
  if ok then
    print("✓ Main plugin setup successful")
    return true
  else
    print("✗ Main plugin setup failed: " .. tostring(err))
    return false
  end
end

-- Run all tests
local function run_tests()
  print("=== Phase 2.1 Component Tests ===\n")
  
  local tests = {
    test_module_loading,
    test_configuration,
    test_component_initialization,
    test_main_plugin
  }
  
  local passed = 0
  local total = #tests
  
  for _, test_func in ipairs(tests) do
    if test_func() then
      passed = passed + 1
    end
  end
  
  print(string.format("\n=== Test Results: %d/%d passed ===", passed, total))
  
  if passed == total then
    print("🎉 All tests passed! Phase 2.1 components are working correctly.")
    return true
  else
    print("❌ Some tests failed. Please check the implementation.")
    return false
  end
end

-- Run the tests
local success = run_tests()
os.exit(success and 0 or 1)
