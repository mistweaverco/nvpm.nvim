--- Bytecode / module cache via Neovim's vim.loader (same mechanism lazy.nvim uses).
local M = {}

--- Enable the Lua module loader with on-disk bytecode cache.
--- Safe to call multiple times; vim.loader.enable is idempotent.
function M.enable()
  if vim.loader and not vim.loader.enabled then
    vim.loader.enable()
  end
end

--- Clear the in-memory module index for a path (or all paths).
--- Does not delete ~/.cache/nvim/luac bytecode files.
---@param path string|nil
function M.reset(path)
  if vim.loader and vim.loader.reset then
    vim.loader.reset(path)
  end
end

---@return boolean
function M.enabled()
  return vim.loader ~= nil and vim.loader.enabled == true
end

return M
