local rtp = require("nvpm.rtp")
local plugin_mod = require("nvpm.plugin")
local event_h = require("nvpm.handlers.event")
local cmd_h = require("nvpm.handlers.cmd")
local ft_h = require("nvpm.handlers.ft")
local keys_h = require("nvpm.handlers.keys")
local require_hook = require("nvpm.require_hook")

local M = {}

local STARTUP_PATTERNS = {
  "plugin/**/*.vim",
  "plugin/**/*.lua",
  "ftdetect/**/*.vim",
  "ftdetect/**/*.lua",
}

local function sort_start_plugins(start_plugins)
  table.sort(start_plugins, function(a, b)
    if a.lazy ~= b.lazy then
      return not a.lazy
    end
    if (a.priority or 50) ~= (b.priority or 50) then
      return (a.priority or 50) > (b.priority or 50)
    end
    return (a._order or 0) < (b._order or 0)
  end)
  return start_plugins
end

--- Load non-lazy plugins synchronously during startup (lazy.nvim parity).
--- setup() must run before VimEnter for plugins that register VimEnter/VimLeave handlers.
local function load_startup_plugins(start_plugins, on_done)
  sort_start_plugins(start_plugins)

  for _, plugin in ipairs(start_plugins) do
    if not plugin._loaded then
      plugin_mod.load_plugin(plugin, { sync = true })
    end
  end

  if on_done then
    on_done()
  end
end

function M.startup(cfg, plugins)
  vim.go.loadplugins = false
  rtp.reset_rtp(cfg)
  plugin_mod.set_plugins(plugins)

  local start_plugins = vim.tbl_filter(function(p)
    return not p.lazy
  end, plugins)

  local lazy_plugins = vim.tbl_filter(function(p)
    return p.lazy
  end, plugins)

  -- lazy.nvim runs init() for every plugin before loading start plugins.
  for _, plugin in ipairs(plugins) do
    plugin_mod.run_init(plugin)
  end

  -- Only start plugins go on rtp at startup; lazy plugins are added on first load.
  rtp.prepend_plugin_dirs(start_plugins)

  require_hook.setup(plugins)

  for _, plugin in ipairs(lazy_plugins) do
    event_h.register(plugin)
    cmd_h.register(plugin)
    ft_h.register(plugin)
    keys_h.register(plugin)
  end

  load_startup_plugins(start_plugins, function()
    rtp.source_config_patterns(STARTUP_PATTERNS)
    rtp.source_after_plugins(plugins)
  end)
end

return M
