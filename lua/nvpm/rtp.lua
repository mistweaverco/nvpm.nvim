local util = require("nvpm.util")
local cache = require("nvpm.cache")

local M = {}

---@type table<string, true>
local disabled_plugins = {}

local uv = vim.uv or vim.loop

local function nvpm_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  -- lua/nvpm/rtp.lua → plugin root (realpath for stable vim.loader cache keys)
  local root = vim.fn.fnamemodify(source, ":p:h:h:h")
  return (vim.uv or vim.loop).fs_realpath(root) or root
end

function M.setup(cfg)
  disabled_plugins = {}
  local list = cfg and cfg.performance and cfg.performance.rtp and cfg.performance.rtp.disabled_plugins
  if type(list) == "table" then
    for _, name in ipairs(list) do
      disabled_plugins[name] = true
    end
  end
end

function M.reset_packpath(cfg)
  if not cfg.performance or not cfg.performance.reset_packpath then
    return
  end
  vim.go.packpath = vim.env.VIMRUNTIME or ""
end

function M.reset_rtp(cfg)
  if not cfg.performance or not cfg.performance.rtp or not cfg.performance.rtp.reset then
    return
  end
  local config = vim.fn.stdpath("config") ---@type string
  local data = vim.fn.stdpath("data") ---@type string
  local runtime = vim.env.VIMRUNTIME
  local me = nvpm_root()

  ---@type string[]
  local rtp = {
    config,
    data .. "/site",
    me,
  }
  if runtime and runtime ~= "" then
    rtp[#rtp + 1] = runtime
  end
  rtp[#rtp + 1] = config .. "/after"

  --luacheck: ignore 122
  vim.opt.rtp = rtp
  if cfg.performance.rtp.paths then
    for _, p in ipairs(cfg.performance.rtp.paths) do
      vim.opt.rtp:append(p)
    end
  end
end

function M.ensure_plugin_on_rtp(plugin)
  if not plugin or not plugin.dir or plugin.dir == "" then
    return false
  end
  if plugin._on_rtp then
    return true
  end
  if vim.in_fast_event() then
    return false
  end
  if not util.is_dir(plugin.dir) then
    return false
  end
  vim.opt.rtp:prepend(plugin.dir)
  plugin._on_rtp = true
  -- Only reset if this path may have been indexed empty earlier.
  cache.reset(plugin.dir)
  return true
end

--- Batch-prepend start plugin dirs onto rtp (one assignment, no per-plugin cache.reset).
---@param plugins table[]
function M.prepend_plugin_dirs(plugins)
  ---@type string[]
  local dirs = {}
  for _, plugin in ipairs(plugins) do
    local dir = plugin.dir
    if dir and dir ~= "" then
      dirs[#dirs + 1] = dir
      plugin._on_rtp = true
    end
  end
  if #dirs == 0 then
    return
  end

  -- Prefer vim.go.rtp (stable, matches Neovim's own list) over nvim_get_runtime_file.
  ---@type string[]
  local parts = {}
  for i = 1, #dirs do
    parts[#parts + 1] = dirs[i]
  end
  for path in vim.gsplit(vim.go.rtp, ",", { plain = true }) do
    if path ~= "" then
      parts[#parts + 1] = path
    end
  end
  vim.go.rtp = table.concat(parts, ",")
end

--- Recursively collect .lua / .vim files under dir (uv.fs_scandir, like lazy.nvim).
---@param dir string
---@param fn fun(path: string, name: string, t: string)
local function walk(dir, fn)
  local handle = uv.fs_scandir(dir)
  if not handle then
    return
  end
  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local path = dir .. "/" .. name
    if t == "directory" then
      walk(path, fn)
    elseif t == "file" or t == "link" then
      fn(path, name, t)
    end
  end
end

--- Source plugin/ftdetect/after scripts under a root (plugin dir or config).
---@param root string
---@param subdir string e.g. "plugin", "ftdetect", "after/plugin"
function M.source_runtime(root, subdir)
  if not root or root == "" then
    return
  end
  local dir = root .. "/" .. subdir
  -- Cheap existence check avoids scandir on the common empty case.
  if not uv.fs_stat(dir) then
    return
  end
  ---@type string[]
  local files = {}
  walk(dir, function(path, name, t)
    local ext = name:sub(-3)
    local basename = name:sub(1, -5)
    if (t == "file" or t == "link") and (ext == "lua" or ext == "vim") and not disabled_plugins[basename] then
      files[#files + 1] = path
    end
  end)
  table.sort(files)
  for _, f in ipairs(files) do
    vim.cmd("source " .. vim.fn.fnameescape(f))
  end
end

---@param plugin table
---@param subdir string
function M.source_plugin_subdir(plugin, subdir)
  if plugin and plugin.dir then
    M.source_runtime(plugin.dir, subdir)
  end
end

function M.source_config_subdir(subdir)
  M.source_runtime(vim.fn.stdpath("config"), subdir)
end

--- Source ftdetect scripts inside the filetypedetect augroup (lazy.nvim parity).
---@param plugin table
function M.source_ftdetect(plugin)
  if not plugin or not plugin.dir or plugin._ftdetect then
    return
  end
  plugin._ftdetect = true
  local dir = plugin.dir .. "/ftdetect"
  if not uv.fs_stat(dir) then
    return
  end
  vim.cmd("augroup filetypedetect")
  M.source_runtime(plugin.dir, "ftdetect")
  vim.cmd("augroup END")
end

--- Source VIMRUNTIME/filetype.lua once so ftdetect hooks work (lazy.nvim parity).
function M.source_filetype()
  local path = (vim.env.VIMRUNTIME or "") .. "/filetype.lua"
  if path ~= "/filetype.lua" and uv.fs_stat(path) then
    vim.cmd("source " .. vim.fn.fnameescape(path))
  end
end

function M.source_after_plugins(plugins)
  for _, plugin in ipairs(plugins) do
    if (plugin._loaded or not plugin.lazy) and plugin.dir then
      -- Skip empty after/ trees (common); one stat beats a failed scandir walk.
      if uv.fs_stat(plugin.dir .. "/after") then
        M.source_runtime(plugin.dir, "after/plugin")
      end
    end
  end
  M.source_config_subdir("after/plugin")
end

return M
