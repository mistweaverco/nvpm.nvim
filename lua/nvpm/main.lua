local M = {}

--- Same normalization as lazy.nvim Util.normname.
function M.normname(name)
  if not name then
    return ""
  end
  return name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", "")
end

local function walkmods(root, fn)
  local function walk(path, modprefix)
    modprefix = modprefix or ""
    local handle = vim.uv.fs_scandir(path)
    if not handle then
      return
    end
    while true do
      local name, t = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local child = path .. "/" .. name
      if name == "init.lua" then
        fn(modprefix:gsub("%.$", ""), child)
      elseif t == "file" and name:sub(-4) == ".lua" then
        fn(modprefix .. name:sub(1, -5), child)
      elseif t == "directory" then
        walk(child, modprefix .. name .. ".")
      end
    end
  end
  walk(root)
end

--- Resolve main Lua module for config/opts (lazy.nvim Loader.get_main).
---@param plugin table
---@return string|nil
function M.get_main(plugin)
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
  local dir = plugin.dir
  if not dir then
    return nil
  end
  local lua_root = dir .. "/lua"
  if vim.uv.fs_stat(lua_root) == nil then
    return nil
  end

  local normname = M.normname(name)
  local mods = {}
  local exact = nil
  walkmods(lua_root, function(modname)
    if exact then
      return
    end
    if modname ~= "" then
      mods[#mods + 1] = modname
    end
    if M.normname(modname) == normname then
      exact = modname
    end
  end)

  if exact then
    return exact
  end
  return #mods == 1 and mods[1] or nil
end

---@deprecated use get_main(plugin)
function M.guess(name, dir)
  return M.get_main({ name = name, dir = dir, spec = {} })
end

return M
