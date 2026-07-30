#!/usr/bin/env -S nvim -l
-- Headless tests for nvpm performance cache defaults.
-- Run: nvim --headless -l test/cache_test.lua

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

local config = require("nvpm.config")
local cache = require("nvpm.cache")
local rtp = require("nvpm.rtp")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": got " .. vim.inspect(a) .. " want " .. vim.inspect(b))
  end
end

assert_eq(config.defaults.performance.cache.enabled, true)
assert_eq(config.defaults.performance.reset_packpath, true)
assert_eq(config.defaults.performance.rtp.reset, true)

-- find_plugin_dir should not invent missing paths
local util = require("nvpm.util")
assert_eq(util.find_plugin_dir("github:definitely/missing-plugin-xyz"), nil)

local merged = config.merge({
  performance = {
    cache = { enabled = false },
    rtp = { reset = false },
  },
})
assert_eq(merged.performance.cache.enabled, false)
assert_eq(merged.performance.rtp.reset, false)
assert_eq(merged.performance.reset_packpath, true)

-- Enable and verify vim.loader is on.
cache.enable()
assert(cache.enabled(), "vim.loader should be enabled")

-- reset_packpath / reset_rtp should be no-ops when disabled.
local before_packpath = vim.go.packpath
rtp.reset_packpath({ performance = { reset_packpath = false } })
assert_eq(vim.go.packpath, before_packpath)

rtp.reset_packpath({ performance = { reset_packpath = true } })
assert_eq(vim.go.packpath, vim.env.VIMRUNTIME or "")

local cfg = {
  performance = {
    rtp = {
      reset = true,
      paths = {},
    },
  },
}
rtp.reset_rtp(cfg)
local rtp_list = vim.api.nvim_get_runtime_file("", true)
local found_nvpm = false
local found_runtime = false
for _, path in ipairs(rtp_list) do
  if path:find("nvpm", 1, true) then
    found_nvpm = true
  end
  if vim.env.VIMRUNTIME and path == vim.env.VIMRUNTIME then
    found_runtime = true
  end
end
assert(found_nvpm, "reset rtp should keep nvpm on runtimepath")
if vim.env.VIMRUNTIME and vim.env.VIMRUNTIME ~= "" then
  assert(found_runtime, "reset rtp should keep VIMRUNTIME")
end

-- source_runtime should not error on missing dirs
rtp.source_runtime("/tmp/nvpm-does-not-exist-" .. tostring(vim.uv.hrtime()), "plugin")

print("nvpm.nvim cache tests: ok")
vim.cmd("qall!")
