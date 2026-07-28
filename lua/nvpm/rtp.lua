local util = require("nvpm.util")

local M = {}

---@type table<string, true>
local disabled_plugins = {}

function M.setup(cfg)
  disabled_plugins = {}
  local list = cfg and cfg.performance and cfg.performance.rtp and cfg.performance.rtp.disabled_plugins
  if type(list) == "table" then
    for _, name in ipairs(list) do
      disabled_plugins[name] = true
    end
  end
end

function M.reset_rtp(cfg)
  if not cfg.performance or not cfg.performance.rtp or not cfg.performance.rtp.reset then
    return
  end
  local config = vim.fn.stdpath("config")
  local runtime = vim.env.VIMRUNTIME
  --luacheck: ignore
  vim.opt.rtp = runtime and runtime ~= "" and { config, runtime } or { config }
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
  -- Trust _on_rtp for membership; startup batch-prepends start plugins.
  -- Avoid O(|rtp|) fnamemodify scans on every lazy load.
  vim.opt.rtp:prepend(plugin.dir)
  plugin._on_rtp = true
  return true
end

function M.prepend_plugin_dirs(plugins)
  for i = #plugins, 1, -1 do
    local plugin = plugins[i]
    local dir = plugin.dir
    if dir and util.is_dir(dir) then
      vim.opt.rtp:prepend(dir)
      plugin._on_rtp = true
    end
  end
end

local function source_dir_glob(base, pattern)
  local files = vim.fn.globpath(base, pattern, false, true)
  table.sort(files)
  for _, f in ipairs(files) do
    local basename = vim.fn.fnamemodify(f, ":t:r")
    if not disabled_plugins[basename] then
      vim.cmd("source " .. vim.fn.fnameescape(f))
    end
  end
end

function M.source_plugin_dir(plugin, patterns)
  for _, pat in ipairs(patterns) do
    source_dir_glob(plugin.dir, pat)
  end
end

function M.source_config_patterns(patterns)
  local config = vim.fn.stdpath("config")
  for _, pat in ipairs(patterns) do
    source_dir_glob(config, pat)
  end
end

function M.source_after_plugins(plugins)
  for _, plugin in ipairs(plugins) do
    if plugin._loaded or not plugin.lazy then
      source_dir_glob(plugin.dir, "after/plugin/**/*.vim")
      source_dir_glob(plugin.dir, "after/plugin/**/*.lua")
    end
  end
  M.source_config_patterns({ "after/plugin/**/*.vim", "after/plugin/**/*.lua" })
end

return M
