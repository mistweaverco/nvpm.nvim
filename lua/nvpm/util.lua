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

--- Clear session caches (tests / re-setup).
function M.clear_caches()
  dir_cache = {}
end

function M.plugin_dir_from_lock(source_id)
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
  local data = M.get_data_path()
  local sanitized = M.sanitize_repo_path(repo)
  local candidates = {
    data .. M.PS .. "plugins" .. M.PS .. provider .. M.PS .. sanitized,
    data .. M.PS .. "packages" .. M.PS .. provider .. M.PS .. sanitized,
  }
  for _, dir in ipairs(candidates) do
    if M.is_dir(dir) then
      dir_cache[source_id] = dir
      return dir
    end
  end
  dir_cache[source_id] = candidates[1]
  return candidates[1]
end

return M
