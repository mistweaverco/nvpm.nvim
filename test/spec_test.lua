#!/usr/bin/env -S nvim -l
-- Headless tests for nvpm.nvim spec utilities.
-- Run: nvim --headless -l test/spec_test.lua

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

local spec = require("nvpm.spec")
local util = require("nvpm.util")
local paths = require("nvpm.paths")
local build = require("nvpm.build")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": got " .. vim.inspect(a) .. " want " .. vim.inspect(b))
  end
end

assert_eq(spec.normalize_source_id({ "folke/tokyonight.nvim" }), "github:folke/tokyonight.nvim")
assert_eq(
  spec.normalize_source_id({ url = "https://github.com/folke/which-key.nvim.git" }),
  "github:folke/which-key.nvim"
)
assert_eq(util.sanitize_repo_path("folke/tokyonight.nvim"), "folke_tokyonight.nvim")

local plugins_path = util.get_plugins_path()
assert_eq(
  util.plugin_dir_from_lock("github:folke/tokyonight.nvim"),
  plugins_path .. paths.PS .. "github" .. paths.PS .. "folke_tokyonight.nvim"
)

assert(spec.is_lazy({ event = "BufRead" }, { lazy = false }))
assert(not spec.is_lazy({}, { lazy = false }))
assert(not spec.is_lazy({ dir = "/tmp/foo" }, { lazy = false }, false))
assert(spec.is_lazy({ dir = "/tmp/foo", ft = "lua" }, { lazy = false }, false))
assert(spec.is_lazy({ dir = "/tmp/foo" }, { lazy = false }, true))
assert(spec.is_lazy({}, { lazy = true }, false))

if not paths.IS_WINDOWS and not paths.IS_DARWIN then
  assert(paths.get_user_config_dir():match("/%.config$"))
  assert(paths.uses_xdg_data_dir())
  assert_eq(paths.get_config_path(), paths.get_user_config_dir() .. paths.PS .. "nvpm")
  assert(paths.get_data_path():match("/%.local/share/nvpm$"))
  assert(paths.get_lock_path():match("/%.config/nvpm/nvpm%-lock%.json$"))
  assert(paths.get_cache_path():match("/%.cache/nvpm$"))
end

local built = false
local plugin = {
  name = "test-plugin",
  source_id = "test:nvpm-build-stamp",
  dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h"),
  spec = {
    build = function()
      built = true
    end,
  },
}
local done = false
build.start(plugin, function(ok)
  assert(ok)
  done = true
end)
vim.wait(5000, function()
  return done
end, 20)
assert(built)
assert(plugin._built)
assert(build.ready(plugin))

-- Second start should hit the stamp and not run build again.
built = false
plugin._built = false
done = false
build.start(plugin, function(ok)
  assert(ok)
  done = true
end)
vim.wait(5000, function()
  return done
end, 20)
assert(done)
assert(not built)
assert(plugin._built)

print("nvpm.nvim spec tests: ok")
vim.cmd("qall!")
