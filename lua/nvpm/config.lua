local M = {}

M.defaults = {
  defaults = {
    lazy = false,
    cond = nil,
  },
  dev = {
    path = "~/projects",
    patterns = {},
    fallback = false,
  },
  performance = {
    rtp = {
      reset = false,
      paths = {},
      disabled_plugins = {},
    },
  },
  git = {
    url_format = "https://github.com/%s.git",
  },
}

M.unsupported_opts = {
  "checker",
  "ui",
  "install",
  "rocks",
  "pkg",
  "lockfile",
  "change_detection",
  "profiling",
  "concurrency",
  "headless",
  "diff",
  "readme",
  "state",
}

function M.merge(user)
  user = user or {}
  local cfg = vim.deepcopy(M.defaults)
  for k, v in pairs(user) do
    if k ~= "spec" and k ~= "import" and type(v) == "table" and type(cfg[k]) == "table" then
      cfg[k] = vim.tbl_deep_extend("force", cfg[k], v)
    else
      cfg[k] = v
    end
  end
  return cfg
end

return M
