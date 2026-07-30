local util = require("nvpm.util")

local M = {}

---@type table<string, table>|nil
local cached_index = nil

--- Clear cached lock index (tests / re-setup).
function M.clear_cache()
  cached_index = nil
end

---@return table<string, table> sourceId -> lock entry
function M.load()
  if cached_index then
    return cached_index
  end
  local path = util.get_lock_path()
  if not util.is_file(path) then
    util.warn_once("lock_missing", "nvpm: lock file not found at " .. path)
    cached_index = {}
    return cached_index
  end
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data then
    util.warn_once("lock_read", "nvpm: could not read " .. path)
    cached_index = {}
    return cached_index
  end
  local content = table.concat(data, "\n")
  local decoded = vim.json.decode(content)
  if type(decoded) ~= "table" or type(decoded.packages) ~= "table" then
    cached_index = {}
    return cached_index
  end
  local index = {}
  for _, pkg in ipairs(decoded.packages) do
    if type(pkg) == "table" and pkg.sourceId then
      index[pkg.sourceId] = pkg
    end
  end
  cached_index = index
  return index
end

function M.is_neovim_plugin(entry)
  return type(entry) == "table" and entry.extras and entry.extras.kind == "neovim-plugin"
end

--- Commit/version from lock for build stamps (loads lock on first use).
---@param source_id string|nil
---@return string|nil
function M.commit_for(source_id)
  if not source_id then
    return nil
  end
  local entry = M.load()[source_id]
  if not entry then
    return nil
  end
  local rev = entry.commit or entry.version
  if rev and rev ~= "" then
    return rev
  end
  return nil
end

function M.resolve_dir(source_id, lock_index)
  lock_index = lock_index or M.load()
  local entry = lock_index[source_id]
  if not entry then
    util.warn_once(
      "missing_lock_" .. source_id,
      ("nvpm: %s not in nvpm-lock.json; run: nvpm add %s"):format(source_id, source_id)
    )
    return nil
  end
  if not M.is_neovim_plugin(entry) then
    util.warn_once(
      "not_plugin_" .. source_id,
      ("nvpm: %s is not marked neovim-plugin in nvpm-lock.json"):format(source_id)
    )
  end
  local dir = util.plugin_dir_from_lock(source_id)
  if not util.is_dir(dir) then
    util.warn_once(
      "missing_dir_" .. source_id,
      ("nvpm: plugin directory missing for %s; run: nvpm sync packages"):format(source_id)
    )
    return nil
  end
  return dir
end

--- Resolve install dir without requiring lock JSON (path + exists check).
function M.try_resolve_dir(source_id, lock_index)
  local dir = util.find_plugin_dir(source_id)
  if dir then
    return dir
  end
  -- Optional warnings when lock is available and entry exists but dir missing.
  if lock_index then
    local entry = lock_index[source_id]
    if entry then
      if not M.is_neovim_plugin(entry) then
        util.warn_once(
          "not_plugin_" .. source_id,
          ("nvpm: %s is not marked neovim-plugin in nvpm-lock.json"):format(source_id)
        )
      end
      util.warn_once(
        "missing_dir_" .. source_id,
        ("nvpm: plugin directory missing for %s; run: nvpm sync packages"):format(source_id)
      )
    end
  end
  return nil
end

return M
