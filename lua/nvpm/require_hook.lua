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
  module_to_plugin[mod] = plugin
  local top = mod:match("^[^%.]+")
  if top and top ~= mod then
    module_to_plugin[top] = plugin
  end
end

--- Register cheap mappings only: name, explicit/cheap main, top-level lua/ entries.
--- Full lua/ tree walks are deferred until get_main runs on actual load.
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
  if plugin.dir then
    for _, mod in ipairs(main_mod.list_topmods(plugin.dir)) do
      register_module(mod, plugin)
    end
  end
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
  local top = modname:match("^[^%.]+")
  if top and top ~= modname then
    return module_to_plugin[top]
  end
  return nil
end

--- Register all plugins so require() can resolve modules even when rtp changed after startup.
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
  if not searchers or searchers._nvpm_wrapped then
    return
  end

  local lua_loader = searchers[2]
  if type(lua_loader) ~= "function" then
    return
  end

  searchers[2] = function(modname)
    local plugin = M.get(modname) or plugin_mod.get_by_module(modname)
    if plugin then
      if vim.in_fast_event() then
        if not plugin._on_rtp then
          vim.schedule(function()
            rtp.ensure_plugin_on_rtp(plugin)
            load_for_require(plugin)
          end)
          return nil
        end
      elseif not rtp.ensure_plugin_on_rtp(plugin) then
        return nil
      end
      if plugin._loading or plugin._configuring or plugin._building then
        return lua_loader(modname)
      end
      if build_mod.needs_build(plugin) and not build_mod.ready(plugin) then
        if vim.in_fast_event() then
          return nil
        end
        plugin_mod.prepare_for_build(plugin)
        build_mod.start(plugin, function(ok)
          if ok then
            load_for_require(plugin)
          end
        end, { sync = true })
        return nil
      end
      if not plugin._loaded and not plugin._loading then
        load_for_require(plugin)
      end
    end
    return lua_loader(modname)
  end
  searchers._nvpm_wrapped = true
end

return M
