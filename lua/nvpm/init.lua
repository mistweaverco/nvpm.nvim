local util = require("nvpm.util")
local config_mod = require("nvpm.config")
local spec = require("nvpm.spec")
local load_mod = require("nvpm.load")
local plugin_mod = require("nvpm.plugin")
local profile = require("nvpm.profile")
local cache = require("nvpm.cache")
local rtp = require("nvpm.rtp")

local M = {}

local _state = {
  plugins = {},
  config = nil,
}

local function keep_cli_first()
  util.prepend_bin_to_path()
  rtp.promote_managed()
end

local function warn_unsupported_opts(opts)
  for _, key in ipairs(config_mod.unsupported_opts) do
    if opts[key] ~= nil then
      util.warn_once("opt_" .. key, ("nvpm: config.%s is ignored; use the nvpm CLI instead"):format(key))
    end
  end
end

---Initialize plugin management with the given options.
---@type function|NvpmConfig
---@param cfg NvpmConfig
---@param opts NvpmConfig|NvpmSpec[]|NvpmSpec
local function manage_packages(cfg, opts)
  local specs = opts

  if opts.spec or opts.import or opts.defaults or opts.dev or opts.performance then
    specs = opts.spec or { { import = opts.import } }
    warn_unsupported_opts(opts)
  end

  -- Bytecode + indexed module cache (same class of optimization as lazy.nvim).
  -- Prefer enabling via bootstrap.setup before require("nvpm"); this covers direct setup().
  if cfg.performance and cfg.performance.cache and cfg.performance.cache.enabled ~= false then
    profile.track({ start = "cache" })
    cache.enable()
    profile.track()
  end

  -- Resolve plugin dirs from filesystem paths; lock JSON is loaded lazily for builds.
  profile.track({ start = "flatten" })
  local flat = spec.flatten_specs(specs, cfg)
  profile.track()

  profile.track({ start = "resolve" })
  local plugins = spec.resolve_plugins(flat, cfg, nil)
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
end

---Initialize `nvpm` with the given options.
---@type function|NvpmConfig
function M.setup(opts)
  profile.reset()
  profile.track({ start = "setup" })

  keep_cli_first()

  if type(opts) == "string" then
    opts = { opts }
  end
  opts = opts or {}

  local cfg = config_mod.merge(opts)

  if cfg.pkg.loader then
    manage_packages(cfg, opts)
  end

  -- Re-assert after start plugins (mason et al. may prepend PATH/rtp during setup).
  keep_cli_first()
  if vim.v.vim_did_enter == 1 then
    vim.schedule(keep_cli_first)
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("nvpm_cli_precedence", { clear = true }),
      once = true,
      callback = keep_cli_first,
    })
  end

  -- Register after start plugins so require("nvpm.lsp") / treesitter runs on slim rtp
  -- and FS discovery is deferred to first BufEnter / FileType.
  if cfg.lsp and cfg.lsp.loader then
    profile.track({ start = "lsp" })
    require("nvpm.lsp").loader()
    profile.track()
  end

  if cfg.treesitter and cfg.treesitter.loader then
    profile.track({ start = "tree-sitter" })
    require("nvpm.treesitter").loader()
    profile.track()
  end
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
