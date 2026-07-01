local function normalize_path(path)
  local parts = {}
  local is_windows = vim.loop.os_uname().sysname == "Windows_NT"

  -- Convert Windows backslashes to forward slashes for consistency
  if is_windows then
    path = path:gsub("\\", "/")
  end

  for part in string.gmatch(path, "[^/]+") do
    if part == ".." then
      if #parts > 0 then
        table.remove(parts) -- Go up one directory
      end
    elseif part ~= "." and part ~= "" then
      table.insert(parts, part)
    end
  end

  local normalized = (is_windows and "" or "/") .. table.concat(parts, "/")

  -- Convert backslashes for Windows paths
  if is_windows then
    normalized = normalized:gsub("/", "\\")
  end

  return normalized
end

local IS_WINDOWS = vim.loop.os_uname().sysname == "Windows_NT"
local PS = IS_WINDOWS and "\\" or "/"
local PATH_SEPARATOR = IS_WINDOWS and ";" or ":"

local getHomePath = function()
  local path = os.getenv("NVPM_HOME") or vim.fn.stdpath("config") .. PS .. ".." .. PS .. "nvpm"
  return normalize_path(path)
end

local getBinPath = function()
  return getHomePath() .. PS .. "bin"
end

vim.env.PATH = getBinPath()
  .. PATH_SEPARATOR
  .. vim.env.PATH
vim.fn.setenv("PATH", vim.env.PATH)

return {
  setup = function() end,
}
