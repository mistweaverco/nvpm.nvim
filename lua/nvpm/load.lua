local rtp = require("nvpm.rtp")
local plugin_mod = require("nvpm.plugin")
local event_h = require("nvpm.handlers.event")
local cmd_h = require("nvpm.handlers.cmd")
local ft_h = require("nvpm.handlers.ft")
local keys_h = require("nvpm.handlers.keys")
local require_hook = require("nvpm.require_hook")
local profile = require("nvpm.profile")

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
      profile.track({ plugin = plugin.name, start = "start" })
      plugin_mod.load_plugin(plugin, { sync = true })
      profile.track()
    end
  end

  if on_done then
    on_done()
  end
end

function M.startup(cfg, plugins)
  profile.track({ start = "startup" })

  vim.go.loadplugins = false
  rtp.setup(cfg)
  rtp.reset_rtp(cfg)
  plugin_mod.set_plugins(plugins)

  local start_plugins = vim.tbl_filter(function(p)
    return not p.lazy
  end, plugins)

  local lazy_plugins = vim.tbl_filter(function(p)
    return p.lazy
  end, plugins)

  -- lazy.nvim runs init() for every plugin before loading start plugins.
  profile.track({ start = "init" })
  for _, plugin in ipairs(plugins) do
    plugin_mod.run_init(plugin)
  end
  profile.track()

  -- Only start plugins go on rtp at startup; lazy plugins are added on first load.
  profile.track({ start = "rtp" })
  rtp.prepend_plugin_dirs(start_plugins)
  profile.track()

  profile.track({ start = "require_hook" })
  require_hook.setup(plugins)
  profile.track()

  profile.track({ start = "handlers" })
  for _, plugin in ipairs(lazy_plugins) do
    event_h.register(plugin)
    cmd_h.register(plugin)
    ft_h.register(plugin)
    keys_h.register(plugin)
  end
  profile.track()

  profile.track({ start = "start" })
  load_startup_plugins(start_plugins, function()
    profile.track({ start = "config_plugin" })
    rtp.source_config_patterns(STARTUP_PATTERNS)
    profile.track()
    profile.track({ start = "after" })
    rtp.source_after_plugins(plugins)
    profile.track()
  end)
  profile.track()

  profile.track()
end

return M
