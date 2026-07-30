stds.nvim = {
  read_globals = { "jit" },
}

std = "lua51+nvim"

read_globals = {
  "vim",
  "unpack",
}

globals = {
  "vim.g",
  "vim.b",
  "vim.w",
  "vim.o",
  "vim.bo",
  "vim.wo",
  "vim.go",
  "vim.env",
}

ignore = {
  "631", -- line too long
}
