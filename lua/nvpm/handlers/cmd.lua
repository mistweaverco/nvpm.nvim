local plugin_mod = require("nvpm.plugin")

local M = {}

function M.register(plugin)
  local cmds = plugin.spec.cmd
  if not cmds then
    return
  end
  if type(cmds) == "string" then
    cmds = { cmds }
  end
  for _, cmd in ipairs(cmds) do
    local name = cmd
    if type(cmd) == "table" then
      name = cmd[1] or cmd.cmd
    end
    if type(name) == "string" and name ~= "" then
      vim.api.nvim_create_user_command(name, function()
        plugin_mod.load_plugin(plugin, {
          sync = true,
          on_done = function()
            vim.cmd(name)
          end,
        })
      end, { nargs = "?", complete = "command" })
    end
  end
end

return M
