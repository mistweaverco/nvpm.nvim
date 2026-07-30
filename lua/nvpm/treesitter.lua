-- Tree-sitter 🌳
local M = {}

---Register FileType autostart; discover site/parser binaries on first FileType (not at setup).
M.loader = function()
  local installed_parsers ---@type string[]|nil

  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      if not installed_parsers then
        installed_parsers = vim.fn.globpath(vim.fn.stdpath("data") .. "/site/parser", "*.{so,dylib,dll}", true, true)
        for i, parser in ipairs(installed_parsers) do
          installed_parsers[i] = vim.fn.fnamemodify(parser, ":t:r")
        end
      end
      if not vim.list_contains(installed_parsers, args.match) then
        return
      end
      vim.treesitter.start(args.buf)
    end,
  })
end

return M
