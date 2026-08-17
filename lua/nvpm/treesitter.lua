-- Tree-sitter 🌳
local M = {}

---Register FileType autostart; discover site/parser binaries on first FileType (not at setup).
---CLI-installed parsers (nvpm --integrate neovim) are loaded by explicit path so they
---win over bundled / plugin copies on runtimepath.
M.loader = function()
  local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
  ---@type table<string, string>|nil lang -> parser library path
  local installed

  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      if not installed then
        installed = {}
        local files = vim.fn.globpath(parser_dir, "*.{so,dylib,dll}", true, true)
        for _, parser in ipairs(files) do
          installed[vim.fn.fnamemodify(parser, ":t:r")] = parser
        end
      end
      local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype) or args.match
      local parser_file = installed[lang] or installed[args.match]
      if not parser_file then
        return
      end
      if pcall(vim.treesitter.language.add, lang, { path = parser_file }) then
        pcall(vim.treesitter.start, args.buf, lang)
      end
    end,
  })
end

return M
