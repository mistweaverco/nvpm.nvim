local plugin_mod = require("nvpm.plugin")
local build_mod = require("nvpm.build")
local rtp = require("nvpm.rtp")
local main_mod = require("nvpm.main")

local M = {}

local module_to_plugin = {}

local function register_module(mod, plugin)
  if not mod or mod == "" then
    return
  end
  -- Only register the exact module name. Do NOT claim the top-level namespace
  -- (e.g. mini.indentscope must not own require("mini.icons")).
  module_to_plugin[mod] = plugin
end

--- Register name / cheap main for all plugins.
--- For lazy plugins, also index top-level lua/ entries (for require-triggered load).
--- Directory topmods like lua/mini/ register as "mini" only when that plugin's
--- main/name matches; nested packages are registered via explicit main when known.
local function register_plugin(plugin)
  if plugin.module == false then
    return
  end
  register_module(plugin.name, plugin)
  local cheap = main_mod.guess_main_cheap(plugin)
  if cheap then
    plugin._main = cheap
    register_module(cheap, plugin)
  end
  if plugin.lazy and plugin.dir then
    for _, mod in ipairs(main_mod.list_topmods(plugin.dir)) do
      local norm_plugin = main_mod.normname(plugin.name)
      local norm_mod = main_mod.normname(mod)
      if norm_plugin == norm_mod or mod == (plugin._main or cheap) then
        register_module(mod, plugin)
      else
        -- Shared package dirs (e.g. lua/mini/): only claim single-file lua/<mod>.lua.
        local file = plugin.dir .. "/lua/" .. mod .. ".lua"
        if vim.uv.fs_stat(file) then
          register_module(mod, plugin)
        end
      end
    end
  end
end

local function module_in_plugin(modname, plugin)
  if not plugin.dir or not vim.loader or not vim.loader.find then
    return true
  end
  local hits = vim.loader.find(modname, { rtp = false, paths = { plugin.dir } })
  return hits[1] ~= nil
end

local function load_for_require(plugin)
  if vim.in_fast_event() then
    vim.schedule(function()
      plugin_mod.load_plugin(plugin, { sync = true })
    end)
    return
  end
  plugin_mod.load_plugin(plugin, { sync = true })
end

--- Lookup plugin by module name from the require index.
---@param modname string
---@return table|nil
function M.get(modname)
  if not modname then
    return nil
  end
  local plugin = module_to_plugin[modname]
  if plugin then
    return plugin
  end
  -- Prefix match only when the module actually lives in that plugin (lazy.nvim parity).
  local top = modname:match("^[^%.]+")
  if top and top ~= modname then
    plugin = module_to_plugin[top]
    if plugin and module_in_plugin(modname, plugin) then
      return plugin
    end
  end
  return nil
end

--- Package loader: only handles unloaded lazy plugins (lazy.nvim model).
--- Placed after vim.loader lua+lib loaders so normal/cached requires stay fast.
--- CLI copies still win because their dirs sit first on rtp.
---@param modname string
---@return function|nil
function M.loader(modname)
  -- Hot path: O(1) index only. Do not call get_by_module (O(plugins)) on misses.
  local plugin = M.get(modname)
  if not plugin or plugin.module == false then
    return
  end

  -- Guard shared namespaces: never load a plugin that doesn't contain this module.
  if not module_in_plugin(modname, plugin) then
    return
  end

  -- Start plugins / already loaded: vim.loader already searched rtp.
  if plugin._loaded or (plugin._on_rtp and not plugin.lazy) then
    return
  end

  if vim.in_fast_event() then
    if not plugin._on_rtp then
      vim.schedule(function()
        rtp.ensure_plugin_on_rtp(plugin)
        load_for_require(plugin)
      end)
    end
    return
  end

  if not rtp.ensure_plugin_on_rtp(plugin) then
    return
  end

  if
    (not plugin._loading or not plugin._configuring or not plugin._building)
    and (build_mod.needs_build(plugin) and not build_mod.ready(plugin))
  then
    plugin_mod.prepare_for_build(plugin)
    build_mod.start(plugin, function(ok)
      if ok then
        load_for_require(plugin)
      end
    end, { sync = true })
    return
  elseif not plugin._loaded and not plugin._loading then
    load_for_require(plugin)
  end

  local mod = package.loaded[modname]
  if mod ~= nil then
    return function()
      return mod
    end
  end

  local hits = vim.loader.find(modname, { rtp = false, paths = { plugin.dir } })
  if hits[1] then
    return loadfile(hits[1].modpath)
  end
end

--- Register plugins and install the require-triggered loader (once).
---@param plugins table[]
function M.setup(plugins)
  module_to_plugin = {}
  for _, plugin in ipairs(plugins) do
    register_plugin(plugin)
  end

  if not package.loaded["nvpm._loader"] then
    package.preload["nvpm._loader"] = function()
      return true
    end
  end

  local searchers = package.loaders
  if not searchers or searchers._nvpm_loader then
    return
  end

  -- After vim.loader.enable: [2]=lua cache, [3]=lib cache. Insert after both so
  -- failed lib/lua lookups don't pay our cost unless the module maps to a plugin.
  local insert_at = 4
  if not (vim.loader and vim.loader.enabled) then
    insert_at = 3
  end
  table.insert(searchers, insert_at, M.loader)
  searchers._nvpm_loader = true
end

return M
