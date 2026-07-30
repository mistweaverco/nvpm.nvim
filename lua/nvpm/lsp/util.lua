---@type table<string>
local lsp_config_name_cache = {}

---Shortcut for `vim.lsp` to avoid typing it out every time.
local lsp = vim.lsp

local M = { path = {} }

---@class LspConfig
---@field log_level number Log level for LSP messages (default: `vim.lsp.protocol.MessageType.Warning`)
---@field message_level number Log level for LSP messages (default: `vim.lsp.protocol MessageType.Warning`)
---@field settings table Settings to pass to the LSP server (default: `{}`)
---@field init_options table Initialization options to pass to the LSP server (default: `{}`)
---@field handlers table Handlers to pass to the LSP server (default: `{}`)
---@field autostart boolean Whether to automatically start the LSP server (default: `true`)
---@field capabilities lsp.ClientCapabilities Capabilities to pass to the LSP server (default: `vim.lsp.protocol.make_client_capabilities()`)

---@type table<string, any>
M.default_config = {
  log_level = lsp.protocol.MessageType.Warning,
  message_level = lsp.protocol.MessageType.Warning,
  settings = vim.empty_dict(),
  init_options = vim.empty_dict(),
  handlers = {},
  autostart = true,
  capabilities = lsp.protocol.make_client_capabilities(),
}

---Escapes wildcard characters in a path for use in glob patterns.
---@param path string The path to escape.
---@return string escaped_path The escaped path.
---@return integer substitutions The number of substitutions made.
local function escape_wildcards(path)
  return path:gsub("([%[%]%?%*])", "\\%1")
end

---Gets the list of LSPs from the `lua/lsp` directory and returns them as a table
---@return table<string>
M.get_lsp_config_names = function()
  if #lsp_config_name_cache > 0 then
    return lsp_config_name_cache
  end
  local lsps = vim.fn.globpath(vim.fs.joinpath(vim.fn.stdpath("config"), "lsp"), "*.lua", true, true)
  for i, l in ipairs(lsps) do
    local name = vim.fn.fnamemodify(l, ":t:r")
    lsp_config_name_cache[i] = name
  end
  return lsp_config_name_cache
end

---Searches for a file or directory matching the given `func` in the ancestors of `startpath`.
---@param startpath string The starting path to search from.
---@param func function A function that takes a path and returns true if it matches the desired file
---@return string|nil The path to the matching file or directory, or nil if not found.
M.search_ancestors = function(startpath, func)
  if func(startpath) then
    return startpath
  end
  local guard = 100
  for path in vim.fs.parents(startpath) do
    -- Prevent infinite recursion if our algorithm breaks
    guard = guard - 1
    if guard == 0 then
      return
    end

    if func(path) then
      return path
    end
  end
end

---Returns a function which matches a filepath against the given glob/wildcard patterns.
---Also works with `zipfile`:/`tarfile`: buffers (via `strip_archive_subpath`).
---@param ... string|table List of glob/wildcard patterns to match against.
function M.root_pattern(...)
  local patterns = vim.iter({ ... }):flatten():totable()
  return function(startpath)
    startpath = M.strip_archive_subpath(startpath)
    for _, pattern in ipairs(patterns) do
      local match = M.search_ancestors(startpath, function(path)
        for _, p in ipairs(vim.fn.glob(table.concat({ escape_wildcards(path), pattern }, "/"), true, true)) do
          if vim.uv.fs_stat(p) then
            return path
          end
        end
      end)

      if match ~= nil then
        local real = vim.uv.fs_realpath(match)
        return real or match -- fallback to original if `realpath` fails
      end
    end
  end
end

---For `zipfile`: or `tarfile`: virtual paths, returns the path to the archive.
---Other paths are returned unaltered.
---@param path string The path to strip the archive subpath from.
---@return string path The path to the archive, or the original path if not a virtual path.
M.strip_archive_subpath = function(path)
  -- Matches regex from `zip.vim` / `tar.vim`
  path = vim.fn.substitute(path, "zipfile://\\(.\\{-}\\)::[^\\\\].*$", "\\1", "")
  path = vim.fn.substitute(path, "tarfile:\\(.\\{-}\\)::.*$", "\\1", "")
  return path
end

function M.get_typescript_server_path(root_dir)
  local project_roots = vim.fs.find("node_modules", { path = root_dir, upward = true, limit = math.huge })
  for _, project_root in ipairs(project_roots) do
    local typescript_path = project_root .. "/typescript"
    local stat = vim.loop.fs_stat(typescript_path)
    if stat and stat.type == "directory" then
      return typescript_path .. "/lib"
    end
  end
  return ""
end

--- Appends `new_names` to `root_files` if `field` is found in any such file in any ancestor of `fname`.
--- @param root_files string[] List of root-marker files to append to.
--- @param new_names string[] Potential root-marker filenames (e.g. `{ 'package.json', 'package.json5' }`) to inspect for the given `field`.
--- @param field string | string[] Field(s) to search for in the given `new_names` files.
--- @param fname string Full path of the current buffer name to start searching upwards from.
--- @param match_mode? 'all' | 'any' Match mode - all or any field passed as `field`
function M.root_markers_with_field(root_files, new_names, field, fname, match_mode)
  local path = vim.fn.fnamemodify(fname, ":h")
  local found = vim.fs.find(new_names, { path = path, upward = true, type = "file" })
  ---@type string[]
  local fields = {}
  if type(field) == "string" then
    fields = { field }
  elseif type(field) == "table" then
    fields = field
  else
    error("field must be a string or a table of strings")
  end
  local to_find = vim.deepcopy(fields)
  local matcher = (match_mode or "any") == "any"
      and function(line)
        return vim.iter(fields):any(function(s)
          return line:find(s)
        end)
      end
    or function(line)
      to_find = vim
        .iter(to_find)
        :filter(function(s)
          return not line:find(s)
        end)
        :totable()
      if #to_find == 0 then
        to_find = vim.deepcopy(root_files)
        return true
      end
      return false
    end
  for _, f in ipairs(found or {}) do
    -- Match the given `field`.
    local file = assert(io.open(f, "r"))
    for line in file:lines() do
      if matcher(line) then
        root_files[#root_files + 1] = vim.fs.basename(f)
        break
      end
    end
    file:close()
  end

  return root_files
end

function M.insert_package_json(root_files, field, fname)
  return M.root_markers_with_field(root_files, { "package.json", "package.json5" }, field, fname)
end

return M
