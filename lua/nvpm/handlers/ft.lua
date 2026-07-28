local plugin_mod = require("nvpm.plugin")

local M = {}

function M.register(plugin)
  local fts = plugin.spec.ft
  if not fts then
    return
  end
  if type(fts) == "string" then
    fts = { fts }
  end
  vim.api.nvim_create_autocmd("FileType", {
    pattern = fts,
    once = true,
    callback = function()
      plugin_mod.load_plugin(plugin, { sync = true })
    end,
  })
end

return M
