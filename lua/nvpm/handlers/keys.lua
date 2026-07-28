local plugin_mod = require("nvpm.plugin")

local M = {}

local function parse_key(key)
  if type(key) == "string" then
    return { lhs = key, rhs = nil, mode = "n", desc = nil }
  end
  if type(key) ~= "table" then
    return nil
  end
  return {
    lhs = key[1],
    rhs = key[2],
    mode = key.mode or "n",
    desc = key.desc,
    ft = key.ft,
    expr = key.expr,
  }
end

local function key_modes(mode)
  if type(mode) == "table" then
    return mode
  end
  return { mode or "n" }
end

local function keymap_opts(parsed)
  local opts = {
    desc = parsed.desc,
    silent = true,
  }
  if parsed.ft then
    opts.buffer = 0
  end
  return opts
end

local function install_rhs(parsed)
  if parsed.rhs == false then
    return
  end
  if type(parsed.rhs) == "function" then
    vim.keymap.set(parsed.mode, parsed.lhs, parsed.rhs, keymap_opts(parsed))
  elseif type(parsed.rhs) == "string" then
    vim.keymap.set(parsed.mode, parsed.lhs, parsed.rhs, keymap_opts(parsed))
  end
end

local function feedkeys_lhs(parsed)
  local lhs = parsed.lhs
  local mode = parsed.mode or "n"
  if mode:sub(-1) == "a" then
    lhs = lhs .. "<C-]>"
  end
  local feed = vim.api.nvim_replace_termcodes("<Ignore>" .. lhs, true, true, true)
  vim.api.nvim_feedkeys(feed, "i", false)
end

function M.register(plugin)
  local keys = plugin.spec.keys
  if not keys then
    return
  end
  if type(keys) == "table" and keys[1] == nil and not keys.lhs then
    return
  end
  local list = keys
  if type(keys) == "string" then
    list = { keys }
  end
  for _, key in ipairs(list) do
    local parsed = parse_key(key)
    if parsed and parsed.lhs then
      for _, mode in ipairs(key_modes(parsed.mode)) do
        local keyspec = {
          lhs = parsed.lhs,
          rhs = parsed.rhs,
          mode = mode,
          desc = parsed.desc,
          ft = parsed.ft,
          expr = parsed.expr,
        }
        vim.keymap.set(keyspec.mode, keyspec.lhs, function()
          pcall(vim.keymap.del, keyspec.mode, keyspec.lhs, { silent = true })
          plugin_mod.load_plugin(plugin, {
            sync = true,
            on_done = function()
              install_rhs(keyspec)
              feedkeys_lhs(keyspec)
            end,
          })
        end, vim.tbl_extend("force", keymap_opts(keyspec), { expr = true }))
      end
    end
  end
end

return M
