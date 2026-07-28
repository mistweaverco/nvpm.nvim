#!/usr/bin/env -S nvim -l
-- Run: nvim --headless -l test/main_test.lua

vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))

local main = require("nvpm.main")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": got " .. vim.inspect(a) .. " want " .. vim.inspect(b))
  end
end

assert_eq(main.normname("fyler.nvim"), "fyler")
assert_eq(main.normname("blink.cmp"), "blinkcmp")
assert_eq(main.normname("which-key.nvim"), "whichkey")

local fyler = { name = "fyler.nvim", dir = root .. "/fixtures/fyler", spec = {} }
assert_eq(main.get_main(fyler), "fyler")

local single = { name = "onlymod.nvim", dir = root .. "/fixtures/single", spec = {} }
assert_eq(main.get_main(single), "onlymod")

local ambiguous = { name = "ambiguous.nvim", dir = root .. "/fixtures/ambiguous", spec = {} }
assert_eq(main.get_main(ambiguous), nil)

local mini = { name = "mini.surround", dir = root .. "/fixtures/ambiguous", spec = {} }
assert_eq(main.get_main(mini), "mini.surround")

local explicit = { name = "foo", dir = root .. "/fixtures/ambiguous", spec = { main = "bar" } }
assert_eq(main.get_main(explicit), "bar")

-- Cached after first resolve
local cached = { name = "fyler.nvim", dir = root .. "/fixtures/fyler", spec = {} }
assert_eq(main.get_main(cached), "fyler")
assert_eq(cached._main, "fyler")
assert_eq(main.get_main(cached), "fyler")

local tops = main.list_topmods(root .. "/fixtures/ambiguous")
table.sort(tops)
assert_eq(vim.inspect(tops), vim.inspect({ "bar", "foo" }))

assert_eq(main.guess_main_cheap({ name = "mini.pairs", spec = {} }), "mini.pairs")
assert_eq(main.guess_main_cheap({ name = "fyler.nvim", spec = {} }), nil)

print("main_test.lua: ok")
