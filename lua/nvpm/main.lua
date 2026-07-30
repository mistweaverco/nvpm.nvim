local M = {}

--- Same normalization as lazy.nvim Util.normname.
function M.normname(name)
  if not name then
    return ""
  end
  return name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", "")
end

--- List top-level lua module names (one scandir of lua/, no recursion).
--- Matches lazy.nvim / vim.loader lsmod - get_main only needs top-level entries.
---@param dir string
---@return string[]
function M.list_topmods(dir)
  local mods = {}
  if not dir or dir == "" then
    return mods
  end
  local lua_root = dir .. "/lua"
  local handle = vim.uv.fs_scandir(lua_root)
  if not handle then
    return mods
  end
  while true do
    local name, t = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if t == "directory" then
      mods[#mods + 1] = name
    elseif t == "file" and name:sub(-4) == ".lua" and name ~= "init.lua" then
      mods[#mods + 1] = name:sub(1, -5)
    end
  end
  return mods
end

--- Cheap main guess without walking the tree (explicit main / mini.*).
---@param plugin table
---@return string|nil
function M.guess_main_cheap(plugin)
  if not plugin then
    return nil
  end
  local spec = plugin.spec or {}
  if spec.main then
    return spec.main
  end
  local name = plugin.name
  if not name then
    return nil
  end
  if name ~= "mini.nvim" and name:match("^mini%..*$") then
    return name
  end
  return nil
end

--- Resolve main Lua module for config/opts (lazy.nvim Loader.get_main).
--- Uses top-level lua/ entries only (not a full tree walk) - same as lazy's Cache.find("*").
--- Result is cached on plugin._main (false means resolved to nil).
---@param plugin table
---@return string|nil
function M.get_main(plugin)
  if not plugin then
    return nil
  end
  if plugin._main ~= nil then
    return plugin._main ~= false and plugin._main or nil
  end

  local cheap = M.guess_main_cheap(plugin)
  if cheap then
    plugin._main = cheap
    return cheap
  end

  local name = plugin.name
  if not name then
    plugin._main = false
    return nil
  end

  local dir = plugin.dir
  if not dir then
    plugin._main = false
    return nil
  end

  local normname = M.normname(name)
  local exact = nil
  local mods = M.list_topmods(dir)
  for _, modname in ipairs(mods) do
    if M.normname(modname) == normname then
      exact = modname
      break
    end
  end

  local result = exact or (#mods == 1 and mods[1] or nil)
  plugin._main = result or false
  return result
end

---@deprecated use get_main(plugin)
function M.guess(name, dir)
  return M.get_main({ name = name, dir = dir, spec = {} })
end

return M
