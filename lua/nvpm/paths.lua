--- NVPM path helpers aligned with nvpm-client (internal/lib/files/root.go).
--- Standalone module (no nvpm deps) so bootstrap.lua can dofile() it.
local M = {}

local uname = vim.loop.os_uname()
local IS_WINDOWS = uname.sysname == "Windows_NT"
local IS_DARWIN = uname.sysname == "Darwin"
local PS = IS_WINDOWS and "\\" or "/"

M.IS_WINDOWS = IS_WINDOWS
M.IS_DARWIN = IS_DARWIN
M.PS = PS

local function env(name)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return nil
  end
  return value
end

function M.normalize_path(path)
  if not path or path == "" then
    return path
  end
  if IS_WINDOWS then
    path = path:gsub("\\", "/")
  end
  local parts = {}
  for part in string.gmatch(path, "[^/]+") do
    if part == ".." then
      if #parts > 0 then
        table.remove(parts)
      end
    elseif part ~= "." and part ~= "" then
      table.insert(parts, part)
    end
  end
  local normalized = (#parts == 0 and (IS_WINDOWS and "" or "/")) or table.concat(parts, "/")
  if not IS_WINDOWS and not normalized:match("^/") then
    normalized = "/" .. normalized
  end
  if IS_WINDOWS then
    normalized = normalized:gsub("/", "\\")
  end
  return normalized
end

--- os.UserConfigDir equivalent ($XDG_CONFIG_HOME, %APPDATA%, or ~/Library/Application Support).
function M.get_user_config_dir()
  local xdg = env("XDG_CONFIG_HOME")
  if xdg then
    return M.normalize_path(xdg)
  end
  if IS_WINDOWS then
    local appdata = env("APPDATA")
    if appdata then
      return M.normalize_path(appdata)
    end
  end
  local home = vim.env.HOME or vim.fn.expand("~")
  if IS_DARWIN then
    return M.normalize_path(home .. PS .. "Library" .. PS .. "Application Support")
  end
  return M.normalize_path(home .. PS .. ".config")
end

--- Linux/BSD use ~/.local/share for NVPM data; macOS/Windows use the config dir.
function M.uses_xdg_data_dir()
  if IS_WINDOWS or IS_DARWIN then
    return false
  end
  return M.get_user_config_dir():match("%.config") ~= nil
end

--- Config dir ($NVPM_HOME or <user-config-dir>/nvpm). Lock file lives here.
function M.get_config_path()
  local nvpm_home = env("NVPM_HOME")
  if nvpm_home then
    return M.normalize_path(nvpm_home)
  end
  return M.normalize_path(M.get_user_config_dir() .. PS .. "nvpm")
end

--- Data share dir ($NVPM_HOME or platform default).
function M.get_data_path()
  local nvpm_home = env("NVPM_HOME")
  if nvpm_home then
    return M.normalize_path(nvpm_home)
  end
  if M.uses_xdg_data_dir() then
    local home = vim.env.HOME or vim.fn.expand("~")
    return M.normalize_path(home .. PS .. ".local" .. PS .. "share" .. PS .. "nvpm")
  end
  return M.get_config_path()
end

--- Cache dir ($NVPM_CACHE or platform default).
function M.get_cache_path()
  local nvpm_cache = env("NVPM_CACHE")
  if nvpm_cache then
    return M.normalize_path(nvpm_cache)
  end
  if M.uses_xdg_data_dir() then
    local home = vim.env.HOME or vim.fn.expand("~")
    return M.normalize_path(home .. PS .. ".cache" .. PS .. "nvpm")
  end
  if IS_DARWIN then
    local home = vim.env.HOME or vim.fn.expand("~")
    return M.normalize_path(home .. PS .. "Library" .. PS .. "Caches" .. PS .. "nvpm")
  end
  if IS_WINDOWS then
    local localappdata = env("LOCALAPPDATA")
    if localappdata then
      return M.normalize_path(localappdata .. PS .. "nvpm" .. PS .. "cache")
    end
    local appdata = env("APPDATA")
    if appdata then
      return M.normalize_path(appdata .. PS .. "nvpm" .. PS .. "cache")
    end
    local home = vim.env.HOME or vim.fn.expand("~")
    return M.normalize_path(home .. PS .. ".nvpm" .. PS .. "cache")
  end
  local home = vim.env.HOME or vim.fn.expand("~")
  return M.normalize_path(home .. PS .. ".cache" .. PS .. "nvpm")
end

function M.get_bin_path()
  return M.get_data_path() .. PS .. "bin"
end

function M.get_plugins_path()
  return M.get_data_path() .. PS .. "plugins"
end

function M.get_packages_path()
  return M.get_data_path() .. PS .. "packages"
end

function M.get_lock_path()
  return M.get_config_path() .. PS .. "nvpm-lock.json"
end

function M.get_registry_cache_path()
  return M.get_cache_path() .. PS .. "nvpm-registry.json"
end

return M
