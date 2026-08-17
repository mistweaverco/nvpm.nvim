#!/usr/bin/env -S nvim -l
-- Headless tests for CLI package PATH / rtp precedence.
-- Run: nvim --headless -l test/path_test.lua

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

local paths = require("nvpm.paths")
local util = require("nvpm.util")
local rtp = require("nvpm.rtp")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": got " .. vim.inspect(a) .. " want " .. vim.inspect(b))
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(msg or "assert_true failed")
  end
end

local sep = paths.IS_WINDOWS and ";" or ":"
local bin = util.get_bin_path()
local orig_path = vim.env.PATH
local orig_rtp = vim.go.rtp

local function path_parts(value)
  local out = {}
  for part in vim.gsplit(value or "", sep, { plain = true }) do
    if part ~= "" then
      out[#out + 1] = part
    end
  end
  return out
end

local function count_bin(value)
  local n = 0
  for _, part in ipairs(path_parts(value)) do
    if part == bin then
      n = n + 1
    end
  end
  return n
end

-- Mid-PATH entry is moved to the front and not duplicated.
vim.env.PATH = "/usr/bin" .. sep .. bin .. sep .. "/usr/local/bin"
util.prepend_bin_to_path()
local after = path_parts(vim.env.PATH)
assert_eq(after[1], bin, "nvpm bin should be first on PATH")
assert_eq(count_bin(vim.env.PATH), 1, "nvpm bin should appear once")
assert_true(vim.env.PATH:find("/usr/bin", 1, true) ~= nil, "other PATH entries are kept")

-- Already-first stays first.
util.prepend_bin_to_path()
assert_eq(path_parts(vim.env.PATH)[1], bin)
assert_eq(count_bin(vim.env.PATH), 1)

-- Missing entry is prepended.
vim.env.PATH = "/usr/bin" .. sep .. "/usr/local/bin"
util.prepend_bin_to_path()
assert_eq(path_parts(vim.env.PATH)[1], bin)
assert_eq(count_bin(vim.env.PATH), 1)

local plugins_root = util.get_plugins_path()
local packages_root = util.get_packages_path()
assert_true(util.is_cli_install_dir(plugins_root .. "/github/foo"), "plugins descendant is CLI")
assert_true(util.is_cli_install_dir(packages_root .. "/npm/bar"), "packages descendant is CLI")
assert_true(not util.is_cli_install_dir("/tmp/nvpm-not-cli"), "unrelated dir is not CLI")
assert_true(
  not util.is_cli_install_dir(plugins_root .. "-extra/github/foo"),
  "plugins prefix without separator is not CLI"
)

-- CLI-installed plugin dirs occupy the front of rtp, ahead of local dirs.
rtp.setup({})
local cli_dir = plugins_root .. "/github/cli_plugin"
local pkg_dir = packages_root .. "/github/pkg_plugin"
local local_dir = "/tmp/nvpm-local-plugin"
rtp.prepend_plugin_dirs({
  { name = "local", dir = local_dir },
  { name = "pkg", dir = pkg_dir },
  { name = "cli", dir = cli_dir },
})
local rtp_parts = vim.split(vim.go.rtp, ",", { plain = true })
assert_eq(rtp_parts[1], pkg_dir, "first CLI dir keeps relative order among CLI installs")
assert_eq(rtp_parts[2], cli_dir, "second CLI dir follows")
assert_eq(rtp_parts[3], local_dir, "local dir comes after CLI installs")

-- Later prepends (mason-style) cannot keep CLI dirs off the front.
vim.opt.rtp:prepend("/tmp/mason-shadow")
rtp.promote_managed()
rtp_parts = vim.split(vim.go.rtp, ",", { plain = true })
assert_eq(rtp_parts[1], pkg_dir, "promote restores CLI dirs to the front")
assert_true(rtp_parts[4] == "/tmp/mason-shadow" or vim.list_contains(rtp_parts, "/tmp/mason-shadow"))

vim.env.PATH = orig_path
vim.fn.setenv("PATH", orig_path)
vim.go.rtp = orig_rtp

print("nvpm.nvim path tests: ok")
vim.cmd("qall!")
