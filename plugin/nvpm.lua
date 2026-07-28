if vim.g.loaded_nvpm_plugin then
  return
end
vim.g.loaded_nvpm_plugin = true

vim.api.nvim_create_user_command("Nvpm", function(opts)
  local sub = vim.trim(opts.args or "")
  if sub == "" or sub == "profile" then
    local ok, profile = pcall(require, "nvpm.profile")
    if not ok then
      vim.notify("nvpm: profile module unavailable", vim.log.levels.WARN)
      return
    end
    local text = profile.format()
    if vim.v.vim_did_enter == 1 then
      vim.notify(text, vim.log.levels.INFO, { title = "nvpm" })
    else
      print(text)
    end
    return
  end
  vim.notify(("nvpm: unknown command '%s' (try :Nvpm profile)"):format(sub), vim.log.levels.WARN)
end, {
  nargs = "?",
  complete = function()
    return { "profile" }
  end,
})
