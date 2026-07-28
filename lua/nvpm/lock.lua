local util = require("nvpm.util")

local M = {}

---@return table<string, table> sourceId -> lock entry
function M.load()
  local path = util.get_lock_path()
  if not util.is_file(path) then
    util.warn_once("lock_missing", "nvpm: lock file not found at " .. path)
    return {}
  end
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data then
    util.warn_once("lock_read", "nvpm: could not read " .. path)
    return {}
  end
  local content = table.concat(data, "\n")
  local decoded = vim.json.decode(content)
  if type(decoded) ~= "table" or type(decoded.packages) ~= "table" then
    return {}
  end
  local index = {}
  for _, pkg in ipairs(decoded.packages) do
    if type(pkg) == "table" and pkg.sourceId then
      index[pkg.sourceId] = pkg
    end
  end
  return index
end

function M.is_neovim_plugin(entry)
  return type(entry) == "table" and entry.extras and entry.extras.kind == "neovim-plugin"
end

function M.resolve_dir(source_id, lock_index)
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

--- Resolve install dir without warning when the lock entry is missing.
function M.try_resolve_dir(source_id, lock_index)
  local entry = lock_index[source_id]
  local dir = util.plugin_dir_from_lock(source_id)
  if not dir then
    return nil
  end
  if util.is_dir(dir) then
    return dir
  end
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
  return nil
end

return M
