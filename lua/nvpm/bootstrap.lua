--- Bootstrap nvpm.nvim onto rtp before require("nvpm") works.
--- Load via loadfile from init.lua, or require after rtp is set.
local M = {}

M.SELF_SOURCE_ID = "github:mistweaverco/nvpm.nvim"

local _source = debug.getinfo(1, "S").source
if _source:sub(1, 1) == "@" then
  _source = _source:sub(2)
end
local _root = vim.fn.fnamemodify(_source, ":h:h:h")
local _ps = vim.loop.os_uname().sysname == "Windows_NT" and "\\" or "/"
local paths = dofile(_root .. _ps .. "lua" .. _ps .. "nvpm" .. _ps .. "paths.lua")

local PS = paths.PS

local function is_dir(path)
  if not path or path == "" then
    return false
  end
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.type == "directory"
end

local function split_provider_repo(source_id)
  local provider, rest = source_id:match("^([^:]+):(.+)$")
  if not provider then
    return nil, nil
  end
  return provider, rest
end

local function plugin_dir_from_source(source_id)
  local provider, repo = split_provider_repo(source_id)
  if not provider or not repo then
    return nil
  end
  local data = paths.get_data_path()
  local sanitized = repo:gsub("/", "_")
  local candidates = {
    data .. PS .. "plugins" .. PS .. provider .. PS .. sanitized,
    data .. PS .. "packages" .. PS .. provider .. PS .. sanitized,
  }
  for _, dir in ipairs(candidates) do
    if is_dir(dir) then
      return dir
    end
  end
  return candidates[1]
end

---@param source_id string|nil defaults to nvpm.nvim itself
---@return string|nil dir
function M.resolve_plugin_dir(source_id)
  source_id = source_id or M.SELF_SOURCE_ID
  local dir = plugin_dir_from_source(source_id)
  if dir and is_dir(dir) then
    return dir
  end
  if source_id == M.SELF_SOURCE_ID and is_dir(_root) then
    return paths.normalize_path(_root)
  end
  return nil
end

--- Path to bootstrap.lua for loadfile() from init.lua.
---@return string|nil
function M.loader_path()
  local dir = M.resolve_plugin_dir(M.SELF_SOURCE_ID)
  if not dir then
    return nil
  end
  return dir .. PS .. "lua" .. PS .. "nvpm" .. PS .. "bootstrap.lua"
end

--- Prepend nvpm.nvim (or another NVPM plugin) onto rtp.
---@param source_id string|nil
---@return string dir
function M.ensure_rtp(source_id)
  local dir = M.resolve_plugin_dir(source_id)
  if not dir then
    local id = source_id or M.SELF_SOURCE_ID
    error(("nvpm: plugin %s is not installed; run: nvpm add %s"):format(id, id), 0)
  end
  vim.opt.rtp:prepend(dir)
  return dir
end

--- Bootstrap rtp, then run nvpm.setup().
---@param opts table|string|nil
function M.setup(opts)
  M.ensure_rtp(M.SELF_SOURCE_ID)
  require("nvpm").setup(opts)
end

return M
