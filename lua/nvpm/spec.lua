local util = require("nvpm.util")
local lock = require("nvpm.lock")

local M = {}

local SPEC_UNSUPPORTED = {
  version = true,
  build_preload = true,
  build_outputs = true,
}

local SPEC_INSTALL_ONLY = {
  branch = true,
  tag = true,
  commit = true,
  pin = true,
  submodules = true,
}

function M.warn_spec_field(name)
  if SPEC_UNSUPPORTED[name] then
    local msg
    if name == "version" then
      msg = ("nvpm: '%s' in plugin specs is unsupported; use nvpm add / nvpm-lock.json instead"):format(name)
    elseif name == "build_preload" or name == "build_outputs" then
      msg = ("nvpm: '%s' is not a lazy.nvim spec field; use build/config instead"):format(name)
    else
      msg = ("nvpm: '%s' in plugin specs is unsupported"):format(name)
    end
    util.warn_once("spec_" .. name, msg)
  elseif SPEC_INSTALL_ONLY[name] then
    util.warn_once(
      "spec_install_" .. name,
      ("nvpm: '%s' is install-time only; pin versions with nvpm add"):format(name)
    )
  end
end

function M.normalize_source_id(spec)
  if spec.dir then
    return nil
  end
  local url = spec[1] or spec.url
  if not url then
    return nil
  end
  if url:match("^%w+:") and not url:match("^https?://") and not url:match("^git@") then
    return url
  end
  if url:match("^git@") or url:match("%.git$") or url:match("^https?://") then
    local owner, repo = url:match("git@github%.com:([^/]+)/(.+)")
    if owner and repo then
      return "github:" .. owner .. "/" .. repo:gsub("%.git$", "")
    end
    owner, repo = url:match("github%.com[:/]([^/]+)/([^/]+)")
    if owner and repo then
      return "github:" .. owner .. "/" .. repo:gsub("%.git$", "")
    end
    owner, repo = url:match("codeberg%.org[:/]([^/]+)/([^/]+)")
    if owner and repo then
      return "codeberg:" .. owner .. "/" .. repo:gsub("%.git$", "")
    end
    local path, repo_name = url:match("gitlab%.com[:/](.+)/([^/]+)")
    if path and repo_name then
      return "gitlab:" .. path .. "/" .. repo_name:gsub("%.git$", "")
    end
    return url
  end
  if url:match("/") then
    return "github:" .. url:gsub("%.git$", "")
  end
  return "github:" .. url
end

function M.plugin_name_from_spec(spec)
  if spec.name then
    return spec.name
  end
  if spec.dir then
    return vim.fn.fnamemodify(spec.dir, ":t")
  end
  local url = spec[1] or spec.url or ""
  return (url:gsub("%.git$", ""):match("([^/]+)$")) or url
end

local function call_bool(fn, plugin, default)
  if fn == nil then
    return default
  end
  if type(fn) == "boolean" then
    return fn
  end
  if type(fn) == "function" then
    return fn(plugin) ~= false
  end
  return default
end

function M.is_enabled(spec, plugin, defaults)
  if call_bool(spec.enabled, plugin, true) == false then
    return false
  end
  local cond = spec.cond
  if cond == nil then
    cond = defaults and defaults.cond
  end
  return call_bool(cond, plugin, true)
end

function M.is_lazy(spec, defaults, dep_only)
  if spec.lazy ~= nil then
    return spec.lazy
  end
  if dep_only then
    return true
  end
  if defaults and defaults.lazy then
    return true
  end
  if spec.event or spec.cmd or spec.ft or spec.keys then
    return true
  end
  return false
end

function M.collect_imports(specs)
  local out = {}
  local function walk(list)
    for _, spec in ipairs(list or {}) do
      if type(spec) == "string" then
        table.insert(out, spec)
      elseif type(spec) == "table" then
        if spec.import then
          table.insert(out, spec.import)
        end
        if spec.specs then
          walk(spec.specs)
        end
        if spec.dependencies then
          walk(spec.dependencies)
        end
      end
    end
  end
  walk(specs)
  return out
end

function M.load_import(module_name)
  local ok, result = pcall(require, module_name)
  if not ok then
    util.warn_once("import_" .. module_name, "nvpm: failed to import '" .. module_name .. "': " .. tostring(result))
    return {}
  end
  if type(result) ~= "table" then
    return {}
  end
  if result[1] ~= nil then
    return result
  end
  return { result }
end

function M.flatten_specs(input, cfg)
  local flat = {}
  local optional_names = {}
  local order = 0

  local function add_spec(spec, parent)
    if type(spec) == "string" then
      spec = { spec }
    end
    if type(spec) ~= "table" then
      return
    end
    if spec.import then
      local imported = M.load_import(spec.import)
      local overlay = vim.deepcopy(spec)
      overlay.import = nil
      overlay.specs = nil
      for _, s in ipairs(imported) do
        add_spec(vim.tbl_deep_extend("force", vim.deepcopy(s), overlay), parent)
      end
      return
    end
    for k in pairs(SPEC_UNSUPPORTED) do
      if spec[k] ~= nil and not (k == "version" and spec[k] == "*") then
        M.warn_spec_field(k)
      end
    end
    for k in pairs(SPEC_INSTALL_ONLY) do
      if spec[k] ~= nil then
        M.warn_spec_field(k)
      end
    end
    if spec.specs then
      for _, s in ipairs(spec.specs) do
        add_spec(s, spec)
      end
    end
    if spec.optional then
      optional_names[M.plugin_name_from_spec(spec)] = true
    end
    table.insert(flat, { spec = spec, parent = parent, order = order, top_level = parent == nil })
    order = order + 1
    if spec.dependencies then
      for _, dep in ipairs(spec.dependencies) do
        add_spec(dep, spec)
      end
    end
  end

  if type(input) == "string" then
    add_spec({ import = input })
  elseif input[1] ~= nil then
    for _, s in ipairs(input) do
      add_spec(s)
    end
  elseif input.spec then
    for _, s in ipairs(input.spec) do
      add_spec(s)
    end
    if input.import then
      add_spec({ import = input.import })
    end
  else
    add_spec(input)
  end

  -- Drop optional-only specs unless referenced elsewhere
  local referenced = {}
  for _, item in ipairs(flat) do
    local name = M.plugin_name_from_spec(item.spec)
    referenced[name] = true
  end
  local merged = {}
  local by_name = {}
  for _, item in ipairs(flat) do
    local name = M.plugin_name_from_spec(item.spec)
    if item.spec.optional and referenced[name] then
      -- keep if another non-optional spec shares the same source
      goto continue
    end
    if item.spec.optional and optional_names[name] then
      local source = M.normalize_source_id(item.spec) or item.spec.dir
      local used = false
      for _, other in ipairs(flat) do
        if not other.spec.optional then
          local osrc = M.normalize_source_id(other.spec) or other.spec.dir
          if osrc == source then
            used = true
            break
          end
        end
      end
      if not used then
        goto continue
      end
    end
    if by_name[name] then
      by_name[name].spec = vim.tbl_deep_extend("force", by_name[name].spec, item.spec)
      if item.top_level then
        by_name[name].top_level = true
      end
    else
      by_name[name] = item
      table.insert(merged, item)
    end
    ::continue::
  end

  return merged, cfg
end

local function sort_by_dependencies(plugins)
  local by_name = {}
  for _, plugin in ipairs(plugins) do
    by_name[plugin.name] = plugin
  end

  local sorted = {}
  local visiting = {}
  local visited = {}

  local function visit(name)
    if visited[name] then
      return
    end
    if visiting[name] then
      return
    end
    visiting[name] = true
    local plugin = by_name[name]
    if plugin and plugin.spec.dependencies then
      for _, dep in ipairs(plugin.spec.dependencies) do
        local dep_spec = type(dep) == "string" and { dep } or dep
        visit(M.plugin_name_from_spec(dep_spec))
      end
    end
    visiting[name] = nil
    visited[name] = true
    if plugin then
      sorted[#sorted + 1] = plugin
    end
  end

  for _, plugin in ipairs(plugins) do
    visit(plugin.name)
  end
  return sorted
end

function M.resolve_plugins(flat_items, cfg, lock_index)
  local plugins = {}
  local dev_path = util.expand_path(cfg.dev.path or "~/projects")

  for _, item in ipairs(flat_items) do
    local spec = item.spec
    local name = M.plugin_name_from_spec(spec)
    local source_id = M.normalize_source_id(spec)
    local dir = nil

    if spec.dir then
      dir = util.expand_path(spec.dir)
    elseif spec.dev and cfg.dev then
      local dev_dir = dev_path .. util.PS .. name
      if util.is_dir(dev_dir) then
        dir = dev_dir
      end
    end

    if not dir and source_id then
      dir = lock.try_resolve_dir(source_id, lock_index)
    end

    if dir and util.is_dir(dir) then
      local plugin = {
        name = name,
        dir = dir,
        spec = spec,
        source_id = source_id,
        lazy = M.is_lazy(spec, cfg.defaults, not item.top_level),
        priority = spec.priority or 50,
        _order = item.order,
        _loaded = false,
        module = spec.module,
      }
      if M.is_enabled(spec, plugin, cfg.defaults) then
        plugins[#plugins + 1] = plugin
      end
    elseif source_id or spec[1] or spec.url then
      local add_cmd = source_id or ("github:" .. (spec[1] or spec.url):gsub("%.git$", ""))
      local msg
      if item.parent then
        local parent_name = M.plugin_name_from_spec(item.parent)
        msg = ("nvpm: %s is required by %s but not installed; run: nvpm add --plugin neovim %s"):format(
          name,
          parent_name,
          add_cmd
        )
      else
        msg = ("nvpm: %s (%s) is not installed; run: nvpm add --plugin neovim %s"):format(
          name,
          source_id or (spec[1] or spec.url),
          add_cmd
        )
      end
      util.warn_once("unresolved_" .. name, msg)
    end
  end

  plugins = sort_by_dependencies(plugins)

  table.sort(plugins, function(a, b)
    if a.lazy ~= b.lazy then
      return not a.lazy
    end
    if (a.priority or 50) ~= (b.priority or 50) then
      return (a.priority or 50) > (b.priority or 50)
    end
    return (a._order or 0) < (b._order or 0)
  end)

  return plugins
end

return M
