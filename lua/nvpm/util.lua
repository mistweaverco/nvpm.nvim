local paths = require("nvpm.paths")

local M = {}

M.IS_WINDOWS = paths.IS_WINDOWS
M.IS_DARWIN = paths.IS_DARWIN
M.PS = paths.PS

function M.normalize_path(path)
  return paths.normalize_path(path)
end

function M.expand_path(path)
  if not path then
    return path
  end
  if path:sub(1, 1) == "~" then
    local home = vim.env.HOME or vim.fn.expand("~")
    if path == "~" then
      return home
    end
    return home .. path:sub(2)
  end
  return vim.fn.fnamemodify(path, ":p")
end

function M.get_user_config_dir()
  return paths.get_user_config_dir()
end

function M.uses_xdg_data_dir()
  return paths.uses_xdg_data_dir()
end

function M.get_config_path()
  return paths.get_config_path()
end

function M.get_data_path()
  return paths.get_data_path()
end

function M.get_cache_path()
  return paths.get_cache_path()
end

function M.get_bin_path()
  return paths.get_bin_path()
end

function M.get_plugins_path()
  return paths.get_plugins_path()
end

function M.get_packages_path()
  return paths.get_packages_path()
end

function M.get_lock_path()
  return paths.get_lock_path()
end

function M.get_registry_cache_path()
  return paths.get_registry_cache_path()
end

local warned = {}

function M.warn_once(key, msg, level)
  if warned[key] then
    return
  end
  warned[key] = true
  vim.notify(msg, level or vim.log.levels.WARN, { title = "nvpm" })
end

function M.is_dir(path)
  if not path or path == "" then
    return false
  end
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.type == "directory"
end

function M.is_file(path)
  if not path or path == "" then
    return false
  end
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.type == "file"
end

function M.split_provider_repo(source_id)
  local provider, rest = source_id:match("^([^:]+):(.+)$")
  if not provider then
    return nil, nil
  end
  return provider, rest
end

function M.sanitize_repo_path(repo)
  return (repo or ""):gsub("/", "_")
end

local dir_cache = {}
---@type table<string, string>|nil provider/sanitized -> dir
local plugins_index = nil

--- Clear session caches (tests / re-setup).
function M.clear_caches()
  dir_cache = {}
  plugins_index = nil
end

--- One scandir of plugins/<provider>/* → map for O(1) resolve.
local function ensure_plugins_index()
  if plugins_index then
    return plugins_index
  end
  plugins_index = {}
  local root = M.get_plugins_path()
  local uv = vim.uv or vim.loop
  local providers = uv.fs_scandir(root)
  if not providers then
    return plugins_index
  end
  while true do
    local provider, pt = uv.fs_scandir_next(providers)
    if not provider then
      break
    end
    if pt == "directory" then
      local pdir = root .. M.PS .. provider
      local entries = uv.fs_scandir(pdir)
      if entries then
        while true do
          local name, nt = uv.fs_scandir_next(entries)
          if not name then
            break
          end
          if nt == "directory" or nt == "link" then
            plugins_index[provider .. "/" .. name] = pdir .. M.PS .. name
          end
        end
      end
    end
  end
  return plugins_index
end

--- Return install dir for source_id only if it exists (plugins/ then packages/).
---@param source_id string
---@return string|nil
function M.find_plugin_dir(source_id)
  if not source_id then
    return nil
  end
  local cached = dir_cache[source_id]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local provider, repo = M.split_provider_repo(source_id)
  if not provider or not repo then
    dir_cache[source_id] = false
    return nil
  end
  local sanitized = M.sanitize_repo_path(repo)
  local key = provider .. "/" .. sanitized
  local indexed = ensure_plugins_index()[key]
  if indexed then
    dir_cache[source_id] = indexed
    return indexed
  end
  -- Fallback: packages/ (tools installed without --plugin neovim)
  local pkg = M.get_packages_path() .. M.PS .. provider .. M.PS .. sanitized
  if M.is_dir(pkg) then
    dir_cache[source_id] = pkg
    return pkg
  end
  dir_cache[source_id] = false
  return nil
end

function M.plugin_dir_from_lock(source_id)
  if not source_id then
    return nil
  end
  local existing = M.find_plugin_dir(source_id)
  if existing then
    return existing
  end
  -- Path for warnings / expected location even when missing.
  local provider, repo = M.split_provider_repo(source_id)
  if not provider or not repo then
    return nil
  end
  local data = M.get_data_path()
  local sanitized = M.sanitize_repo_path(repo)
  return data .. M.PS .. "plugins" .. M.PS .. provider .. M.PS .. sanitized
end

return M
