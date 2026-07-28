local plugin_mod = require("nvpm.plugin")

local M = {}

local autocmds = {}
local very_lazy_done = false
local very_lazy_scheduled = false

local function ensure_load(plugin)
  if not plugin._loaded then
    plugin_mod.load_plugin(plugin, { sync = true })
  end
end

local function schedule_very_lazy()
  if very_lazy_scheduled then
    return
  end
  very_lazy_scheduled = true
  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      vim.schedule(function()
        very_lazy_done = true
        vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
      end)
    end,
  })
end

function M.register(plugin)
  local events = plugin.spec.event
  if not events then
    return
  end
  if type(events) == "string" then
    events = { events }
  end
  for _, ev in ipairs(events) do
    local event_name = ev
    local pattern = nil
    if type(ev) == "table" then
      event_name = ev.event or ev[1]
      pattern = ev.pattern
    end
    if type(event_name) == "table" then
      for _, e in ipairs(event_name) do
        M.register_single(plugin, e, pattern)
      end
    else
      M.register_single(plugin, event_name, pattern)
    end
  end
end

function M.register_single(plugin, event_name, pattern)
  if event_name == "VeryLazy" then
    schedule_very_lazy()
    if very_lazy_done then
      vim.schedule(function()
        ensure_load(plugin)
      end)
      return
    end
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        ensure_load(plugin)
      end,
    })
    table.insert(autocmds, id)
    return
  end

  local id = vim.api.nvim_create_autocmd(event_name, {
    pattern = pattern or "*",
    once = true,
    callback = function()
      ensure_load(plugin)
    end,
  })
  table.insert(autocmds, id)
end

return M
