-- dotnet-plugin.nvim - .NET Development Suite for Neovim
-- Main plugin entry point

if vim.g.loaded_dotnet_plugin then
  return
end
vim.g.loaded_dotnet_plugin = 1

-- Ensure we're running on Neovim 0.8+
if vim.fn.has('nvim-0.8') == 0 then
  vim.api.nvim_err_writeln('dotnet-plugin.nvim requires Neovim 0.8+')
  return
end

-- Plugin is available but not auto-initialized
-- Users should call require('dotnet-plugin').setup() in their config
