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

--- Resolve performance flags from opts (bare plugin list → defaults = all on).
local function perf_flags(opts)
  local perf = type(opts) == "table" and opts.performance or nil
  return {
    cache = not (perf and perf.cache and perf.cache.enabled == false),
    reset_packpath = not (perf and perf.reset_packpath == false),
    reset_rtp = not (perf and perf.rtp and perf.rtp.reset == false),
    rtp_paths = perf and perf.rtp and perf.rtp.paths or nil,
  }
end

--- Apply packpath/rtp reset before require("nvpm") so module lookup is cheap.
local function early_performance(opts, me)
  local flags = perf_flags(opts)

  if flags.cache and vim.loader then
    vim.loader.enable()
  end

  if flags.reset_packpath then
    vim.go.packpath = vim.env.VIMRUNTIME or ""
  end

  if flags.reset_rtp then
    local config = vim.fn.stdpath("config")
    local data = vim.fn.stdpath("data")
    ---@type string[]
    local rtp = {
      config,
      data .. "/site",
      me,
    }
    if vim.env.VIMRUNTIME and vim.env.VIMRUNTIME ~= "" then
      rtp[#rtp + 1] = vim.env.VIMRUNTIME
    end
    rtp[#rtp + 1] = config .. "/after"
    --luacheck: ignore 122
    vim.opt.rtp = rtp
    if flags.rtp_paths then
      for _, p in ipairs(flags.rtp_paths) do
        vim.opt.rtp:append(p)
      end
    end
  else
    vim.opt.rtp:prepend(me)
  end
end

local _me = M.resolve_plugin_dir(M.SELF_SOURCE_ID)
if _me then
  _me = (vim.uv or vim.loop).fs_realpath(_me) or _me
end

--- Run cache + rtp reset immediately (before setup args are evaluated).
--- Call explicitly if you need custom performance flags before requiring specs:
---   local nvpm = bootstrap(); nvpm.prepare({ performance = {...} }); nvpm.setup({...})
---@param opts table|nil
function M.prepare(opts)
  if not _me then
    _me = M.resolve_plugin_dir(M.SELF_SOURCE_ID)
    if not _me then
      error("nvpm: plugin " .. M.SELF_SOURCE_ID .. " is not installed; run: nvpm add " .. M.SELF_SOURCE_ID, 0)
    end
    _me = (vim.uv or vim.loop).fs_realpath(_me) or _me
  end
  early_performance(opts, _me)
  M._prepared = true
end

-- Auto-prepare with defaults when bootstrap is loaded so that
--   nvpm_bootstrapper().setup({ require("plugins.config.foo"), ... })
-- evaluates those requires with vim.loader + slim rtp already active.
if _me then
  M.prepare(vim.g.nvpm_performance)
end

--- Bootstrap rtp, then run nvpm.setup().
---@param opts table|string|nil
function M.setup(opts)
  if not M._prepared then
    M.prepare(opts)
  elseif type(opts) == "table" and opts.performance then
    -- Re-apply if setup carries explicit performance overrides.
    early_performance(opts, _me)
  end

  require("nvpm").setup(opts)
end

return M
