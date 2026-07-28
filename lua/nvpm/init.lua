local util = require("nvpm.util")
local config_mod = require("nvpm.config")
local lock = require("nvpm.lock")
local spec = require("nvpm.spec")
local load_mod = require("nvpm.load")
local plugin_mod = require("nvpm.plugin")
local profile = require("nvpm.profile")

local M = {}

local _state = {
  plugins = {},
  config = nil,
}

local function bootstrap_path()
  local bin = util.get_bin_path()
  local sep = util.IS_WINDOWS and ";" or ":"
  if not vim.env.PATH:find(bin, 1, true) then
    vim.env.PATH = bin .. sep .. vim.env.PATH
    vim.fn.setenv("PATH", vim.env.PATH)
  end
end

local function warn_unsupported_opts(opts)
  for _, key in ipairs(config_mod.unsupported_opts) do
    if opts[key] ~= nil then
      util.warn_once("opt_" .. key, ("nvpm: config.%s is ignored; use the nvpm CLI instead"):format(key))
    end
  end
end

function M.setup(opts)
  profile.reset()
  profile.track({ start = "setup" })

  bootstrap_path()

  if type(opts) == "string" then
    opts = { opts }
  end
  opts = opts or {}

  local specs = opts
  local cfg = config_mod.defaults
  if opts.spec or opts.import or opts.defaults or opts.dev or opts.performance then
    cfg = config_mod.merge(opts)
    specs = opts.spec or { { import = opts.import } }
    warn_unsupported_opts(opts)
  end

  profile.track({ start = "lock" })
  local lock_index = lock.load()
  profile.track()

  profile.track({ start = "flatten" })
  local flat = spec.flatten_specs(specs, cfg)
  profile.track()

  profile.track({ start = "resolve" })
  local plugins = spec.resolve_plugins(flat, cfg, lock_index)
  profile.track()

  _state.config = cfg
  _state.plugins = plugins

  if #plugins == 0 then
    util.warn_once(
      "no_plugins",
      "nvpm: no plugins were loaded; install them with nvpm add --plugin neovim <pkg> and check :messages"
    )
  end

  load_mod.startup(cfg, plugins)
  profile.track()
end

function M.plugins()
  return _state.plugins
end

function M.load(name)
  local plugin = plugin_mod.get(name)
  if plugin then
    plugin_mod.load_plugin(plugin, { sync = true })
  end
end

--- Return startup profile root and formatted report helpers.
function M.stats()
  return {
    total_ms = profile.total_ms(),
    rows = profile.rows(),
    root = profile.root(),
    format = function()
      return profile.format()
    end,
  }
end

return M
