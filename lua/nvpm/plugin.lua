local main_mod = require("nvpm.main")
local build_mod = require("nvpm.build")
local rtp = require("nvpm.rtp")
local util = require("nvpm.util")
local spec_mod = require("nvpm.spec")

local M = {}

local FTDETECT_PATTERNS = {
  "ftdetect/**/*.vim",
  "ftdetect/**/*.lua",
}

local PLUGIN_SCRIPT_PATTERNS = {
  "plugin/**/*.vim",
  "plugin/**/*.lua",
}

local state = {
  plugins = {},
  by_name = {},
  by_dir = {},
}

function M.reset()
  state.plugins = {}
  state.by_name = {}
  state.by_dir = {}
end

function M.set_plugins(plugins)
  M.reset()
  state.plugins = plugins
  for _, p in ipairs(plugins) do
    state.by_name[p.name] = p
    state.by_dir[p.dir] = p
  end
end

function M.all()
  return state.plugins
end

function M.get(name)
  return state.by_name[name]
end

function M.get_by_dir(dir)
  return state.by_dir[dir]
end

function M.get_by_module(modname)
  for _, plugin in ipairs(state.plugins) do
    if plugin.module == false then
      goto continue
    end
    local mod = plugin.spec.main or main_mod.get_main(plugin)
    if mod and (mod == modname or modname:match("^" .. mod:gsub("%-", "%%-") .. "%.")) then
      return plugin
    end
    ::continue::
  end
end

function M.loaded(plugin)
  return plugin._loaded
end

function M.mark_loaded(plugin)
  plugin._loaded = true
end

function M.run_init(plugin)
  if plugin._init_done then
    return
  end
  plugin._init_done = true
  local init = plugin.spec.init
  if type(init) == "function" then
    init(plugin)
  end
end

function M.prepare_for_build(plugin)
  rtp.ensure_plugin_on_rtp(plugin)
end

function M.prepare_early(plugin)
  if plugin._early_prepared then
    return
  end
  plugin._early_prepared = true
  rtp.ensure_plugin_on_rtp(plugin)
  rtp.source_plugin_dir(plugin, FTDETECT_PATTERNS)
  M.run_init(plugin)
end

function M.prepare_scripts(plugin)
  if plugin._scripts_prepared then
    return
  end
  plugin._scripts_prepared = true
  rtp.source_plugin_dir(plugin, PLUGIN_SCRIPT_PATTERNS)
end

function M.prepare_plugin(plugin)
  if plugin._prepared then
    return
  end
  plugin._prepared = true
  M.prepare_early(plugin)
  M.prepare_scripts(plugin)
end

function M.resolve_opts(plugin)
  local opts = plugin.spec.opts
  if type(opts) == "function" then
    return opts(plugin, {}) or {}
  end
  return opts or {}
end

---@return boolean ok
function M.run_config(plugin)
  plugin._configuring = true
  local ok, err = pcall(function()
    local spec = plugin.spec
    if type(spec.config) == "function" then
      spec.config(plugin, M.resolve_opts(plugin))
      return
    end
    if spec.config or spec.opts then
      local mod_name = main_mod.get_main(plugin)
      if not mod_name then
        error(
          ("Lua module not found for config of %s. Please use a `config()` function instead"):format(plugin.name),
          0
        )
      end
      local req_ok, mod = pcall(require, mod_name)
      if not req_ok then
        error(("require('%s') failed: %s"):format(mod_name, tostring(mod)), 0)
      end
      if type(mod) == "table" and type(mod.setup) == "function" then
        mod.setup(M.resolve_opts(plugin))
      elseif spec.opts ~= nil then
        error(("Module '%s' has no setup() for %s; use a `config()` function instead"):format(mod_name, plugin.name), 0)
      end
    end
  end)
  plugin._configuring = false
  if not ok then
    util.warn_once("config_err_" .. plugin.name, ("nvpm: config failed for %s: %s"):format(plugin.name, tostring(err)))
    return false
  end
  return true
end

local function schedule_after_ui(fn)
  if vim.v.vim_did_enter == 1 then
    vim.defer_fn(fn, 0)
    return
  end
  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      vim.defer_fn(fn, 0)
    end,
  })
end

local function apply_plugin(plugin, on_complete, sync)
  plugin._loading = true

  local function done()
    plugin._loading = false
    if on_complete then
      on_complete()
    end
  end

  local defer_config = build_mod.needs_build(plugin) and not sync

  if defer_config then
    M.prepare_early(plugin)
    schedule_after_ui(function()
      rtp.ensure_plugin_on_rtp(plugin)
      vim.schedule(function()
        if M.run_config(plugin) then
          M.prepare_scripts(plugin)
          done()
        else
          plugin._loading = false
        end
      end)
    end)
    return
  end

  M.prepare_plugin(plugin)
  if M.run_config(plugin) then
    done()
  else
    plugin._loading = false
  end
end

local function flush_load_waiters(plugin, sync)
  local waiters = plugin._load_waiters or {}
  plugin._load_waiters = nil
  for _, cb in ipairs(waiters) do
    if sync then
      cb()
    else
      vim.schedule(cb)
    end
  end
end

local function apply_loaded(plugin, sync)
  local ok, err = pcall(apply_plugin, plugin, function()
    M.mark_loaded(plugin)
    flush_load_waiters(plugin, sync)
  end, sync)
  if not ok then
    util.warn_once("load_err_" .. plugin.name, ("nvpm: error loading %s: %s"):format(plugin.name, tostring(err)))
    M.mark_loaded(plugin)
    flush_load_waiters(plugin, sync)
  end
end

local function load_dependencies(plugin, sync, on_done)
  local deps = plugin.spec and plugin.spec.dependencies
  if not deps or #deps == 0 then
    on_done(true)
    return
  end

  local index = 0
  local function step()
    index = index + 1
    local dep = deps[index]
    if not dep then
      on_done(true)
      return
    end
    local dep_spec = type(dep) == "string" and { dep } or dep
    local dep_name = spec_mod.plugin_name_from_spec(dep_spec)
    local dep_plugin = M.get(dep_name)
    if not dep_plugin then
      util.warn_once(
        "dep_missing_" .. plugin.name .. "_" .. dep_name,
        ("nvpm: %s depends on %s which is not installed"):format(plugin.name, dep_name)
      )
      step()
      return
    end
    M.load_plugin(dep_plugin, {
      sync = sync,
      on_done = function()
        if dep_plugin._loaded then
          step()
        else
          on_done(false)
        end
      end,
    })
  end
  step()
end

local function finish_load(plugin, sync)
  if sync then
    apply_loaded(plugin, true)
    return
  end
  vim.schedule(function()
    apply_loaded(plugin, false)
  end)
end

local function start_load(plugin, opts)
  local sync = opts.sync == true

  local function complete(ok)
    if ok == false then
      plugin._load_started = false
      flush_load_waiters(plugin, sync)
    end
  end

  local function after_dependencies()
    if plugin._built or not build_mod.needs_build(plugin) then
      finish_load(plugin, sync)
      return
    end

    if opts.advance then
      build_mod.start(plugin, function(ok)
        if ok then
          finish_load(plugin, sync)
        else
          complete(false)
        end
      end, { sync = sync })
      return
    end

    build_mod.start(plugin, function(ok)
      if ok == false then
        complete(false)
        return
      end
      finish_load(plugin, sync)
    end, { sync = sync })
  end

  load_dependencies(plugin, sync, function(ok)
    if ok == false then
      complete(false)
      return
    end
    after_dependencies()
  end)
end

function M.load_plugin(plugin, opts)
  opts = opts or {}
  local sync = opts.sync == true

  if plugin._loaded then
    if opts.on_done then
      if sync then
        opts.on_done()
      else
        vim.schedule(opts.on_done)
      end
    end
    return
  end

  if opts.on_done then
    plugin._load_waiters = plugin._load_waiters or {}
    table.insert(plugin._load_waiters, opts.on_done)
  end

  if plugin._load_started then
    return
  end
  plugin._load_started = true

  start_load(plugin, opts)
end

return M
