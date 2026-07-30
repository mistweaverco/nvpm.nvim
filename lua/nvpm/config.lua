local M = {}

---@alias NvpmConfigDefaultsCondFn fun():boolean

---@class NvpmConfigDefaults
---@field lazy boolean
---@field cond NvpmConfigDefaultsCondFn|nil

---@class NvpmConfigDev
---@field path string
---@field patterns string[]
---@field fallback boolean

---@class NvpmConfigPerformanceRtp
---@field reset boolean
---@field paths string[]
---@field disabled_plugins string[]

---@class NvpmConfigPerformance
---@field rtp NvpmConfigPerformanceRtp

---@class NvpmConfigLsp
---@field loader boolean Loads LSP configurations from `vim.fn.stdpath("config")/lsp/*.lua` directory on startup and activates the LSPs on `BufEnter`. Set to `false` to disable.

---@class NvpmConfigTreesitter
---@field loader boolean Loads Tree-sitter parsers from `site/parsers/*.{so,dylib,dll}` on startup. Set to `false` to disable.

---@class NvpmConfigGit
---@field url_format string

---@class NvpmConfig
---@field defaults NvpmConfigDefaults
---@field dev NvpmConfigDev
---@field performance NvpmConfigPerformance
---@field lsp NvpmConfigLsp
---@field treesitter NvpmConfigTreesitter
---@field git NvpmConfigGit

---Default configuration for `nvpm`.
---@type NvpmConfig
M.defaults = {
  defaults = {
    lazy = false,
    cond = nil,
  },
  dev = {
    path = "~/Projects",
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
  treesitter = {
    loader = true,
  },
  lsp = {
    loader = true,
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
