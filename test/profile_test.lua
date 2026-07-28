#!/usr/bin/env -S nvim -l
-- Run: nvim --headless -l test/profile_test.lua

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

local profile = require("nvpm.profile")

local function assert_true(cond, msg)
  if not cond then
    error(msg or "assert_true failed")
  end
end

profile.reset()
profile.track({ start = "outer" })
profile.track({ start = "inner" })
vim.uv.sleep(1)
profile.track()
profile.track()

local rows = profile.rows()
assert_true(#rows >= 2, "expected nested profile rows")
assert_true(rows[1].label:find("outer"), "expected outer span")
assert_true(rows[2].depth == 1, "inner should be nested")

local text = profile.format()
assert_true(text:find("nvpm profile"), "format header")
assert_true(profile.total_ms() >= 0, "total_ms")

print("profile_test.lua: ok")
