local utils = require("nvpm.lsp.util")

-- LSP 📡
local M = {}

---Register BufEnter loader; discover lsp/*.lua names on first trigger (not at setup).
M.loader = function()
  local lsp_config_names ---@type string[]|nil

  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
      if not lsp_config_names then
        lsp_config_names = utils.get_lsp_config_names()
      end
      for _, lsp_config_name in ipairs(lsp_config_names) do
        vim.lsp.enable(lsp_config_name)
      end
      vim.lsp.inlay_hint.enable(false)
    end,
  })
end

return M
