local util = require("nvpm.util")
local rtp = require("nvpm.rtp")

local M = {}

local MAX_CONCURRENT = 2
local active_builds = 0
local build_queue = {}

local function shell_prefix()
  if util.IS_WINDOWS then
    return { "cmd.exe", "/c" }
  end
  return { "sh", "-c" }
end

local function is_ex_command(command)
  return type(command) == "string" and command:match("^%s*:")
end

local function is_lua_ex_command(command)
  return type(command) == "string" and command:match("^%s*:lua%s+")
end

local function notify_id(plugin)
  return "nvpm_build_" .. plugin.name
end

local function notify_building(plugin)
  vim.notify(("Building %s…"):format(plugin.name), vim.log.levels.INFO, {
    title = "nvpm",
    id = notify_id(plugin),
  })
end

local function notify_build_result(plugin, ok, detail)
  if ok then
    vim.notify(("Built %s"):format(plugin.name), vim.log.levels.INFO, {
      title = "nvpm",
      id = notify_id(plugin),
    })
    return
  end
  util.warn_once("build_fail_" .. plugin.name, ("nvpm: build failed for %s: %s"):format(plugin.name, tostring(detail)))
  vim.notify(("Build failed for %s"):format(plugin.name), vim.log.levels.ERROR, {
    title = "nvpm",
    id = notify_id(plugin),
  })
end

local function build_signature(plugin)
  local build = plugin.spec and plugin.spec.build
  if type(build) == "function" then
    return "function"
  end
  if type(build) == "table" then
    return table.concat(build, " ")
  end
  return tostring(build)
end

local function plugin_revision(dir)
  if not dir or dir == "" then
    return "unknown"
  end
  local git = dir .. util.PS .. ".git"
  if util.is_dir(git) or util.is_file(git) then
    local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "HEAD" })
    if vim.v.shell_error == 0 then
      return (out:gsub("%s+$", ""))
    end
  end
  local stat = (vim.uv or vim.loop).fs_stat(dir)
  if stat and stat.mtime then
    return tostring(stat.mtime.sec or stat.mtime)
  end
  return "unknown"
end

local function stamp_key(plugin)
  local id = plugin.source_id or plugin.name or "plugin"
  return (id:gsub("[^%w._%-]", "_"))
end

local function stamp_path(plugin)
  return util.get_cache_path() .. util.PS .. "builds" .. util.PS .. stamp_key(plugin)
end

local function expected_stamp(plugin)
  return vim.fn.sha256(build_signature(plugin) .. "@" .. plugin_revision(plugin.dir))
end

local function read_stamp(plugin)
  local path = stamp_path(plugin)
  if not util.is_file(path) then
    return nil
  end
  local lines = vim.fn.readfile(path)
  if type(lines) ~= "table" or not lines[1] then
    return nil
  end
  return lines[1]
end

local function write_stamp(plugin)
  local path = stamp_path(plugin)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ expected_stamp(plugin) }, path)
end

local function is_build_current(plugin)
  local current = read_stamp(plugin)
  if current == nil or current ~= expected_stamp(plugin) then
    return false
  end
  return true
end

local function flush_waiters(plugin, ok, sync)
  local waiters = plugin._build_waiters or {}
  plugin._build_waiters = nil
  for _, cb in ipairs(waiters) do
    if sync then
      cb(ok)
    else
      vim.schedule(function()
        cb(ok)
      end)
    end
  end
end

local function finish_build(plugin, ok, detail)
  plugin._building = false
  active_builds = math.max(0, active_builds - 1)
  if ok then
    plugin._built = true
    write_stamp(plugin)
  end
  notify_build_result(plugin, ok, detail)
  flush_waiters(plugin, ok)
  M._pump_queue()
end

local function finish_build_safe(plugin, ok, detail)
  vim.schedule(function()
    finish_build(plugin, ok, detail)
  end)
end

local function ensure_build_context(plugin)
  rtp.ensure_plugin_on_rtp(plugin)
end

local function parse_argv(command)
  if type(command) == "table" then
    return command
  end
  if type(command) ~= "string" then
    return nil
  end
  command = vim.trim(command)
  if command == "" or command:match("[|&;<>$`\"']") then
    return nil
  end
  return vim.split(command, "%s+")
end

local function run_lua_ex_command(plugin, command, on_done)
  local code = command:match("^%s*:lua%s+(.*)$")
  vim.schedule(function()
    rtp.ensure_plugin_on_rtp(plugin)
    local fn, err = load(code, "@nvpm-build", "t")
    if not fn then
      on_done(false, err)
      return
    end
    local ok, res = pcall(fn)
    on_done(ok, res)
  end)
end

local function run_ex_command(plugin, dir, command, on_done)
  if is_lua_ex_command(command) then
    run_lua_ex_command(plugin, command, on_done)
    return
  end

  local function run()
    local previous = vim.fn.getcwd()
    local ok, err = pcall(function()
      vim.cmd("cd " .. vim.fn.fnameescape(dir))
      vim.cmd(command)
    end)
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(previous))
    on_done(ok, err)
  end

  if vim.v.vim_did_enter == 1 then
    vim.schedule(run)
    return
  end

  run()
end

local function run_shell_command_async(dir, command, on_done)
  local text = type(command) == "table" and table.concat(command, " ") or command
  local cmd = shell_prefix()
  table.insert(cmd, text)
  if vim.system then
    vim.system(cmd, { cwd = dir }, function(result)
      local ok = result.code == 0
      local detail = result.stderr or result.stdout or ("exit " .. tostring(result.code))
      on_done(ok, detail)
    end)
    return
  end
  vim.schedule(function()
    vim.fn.system(cmd)
    on_done(vim.v.shell_error == 0, "shell exit " .. tostring(vim.v.shell_error))
  end)
end

local function default_build_command(plugin)
  local dir = plugin.dir
  local sh = dir .. util.PS .. "build.sh"
  local ps1 = dir .. util.PS .. "build.ps1"
  local makefile = dir .. util.PS .. "Makefile"

  if util.is_file(sh) then
    return "bash build.sh"
  end
  if util.IS_WINDOWS and util.is_file(ps1) then
    return "powershell -ExecutionPolicy Bypass -File build.ps1"
  end
  if util.is_file(makefile) then
    return "make"
  end
  return nil
end

local function announce_build(plugin)
  vim.schedule(function()
    notify_building(plugin)
    vim.defer_fn(function()
      vim.cmd("redraw")
    end, 0)
  end)
end

local function execute_build_sync(plugin)
  local build = plugin.spec.build
  local dir = plugin.dir

  if type(build) == "function" then
    local ok, detail = pcall(function()
      local result = build(plugin)
      if type(result) == "table" and type(result.wait) == "function" then
        result:wait()
      end
    end)
    return ok, detail
  end

  local command
  if type(build) == "string" or type(build) == "table" then
    command = build
  elseif build == true then
    command = default_build_command(plugin)
    if not command then
      util.warn_once(
        "build_default_" .. plugin.name,
        ("nvpm: build=true for %s but no build.sh, build.ps1, or Makefile found"):format(plugin.name)
      )
      return true
    end
  else
    return false, "unsupported build type"
  end

  if type(command) == "string" and is_ex_command(command) then
    local ok, detail = true, nil
    if is_lua_ex_command(command) then
      local code = command:match("^%s*:lua%s+(.*)$")
      rtp.ensure_plugin_on_rtp(plugin)
      local fn, err = load(code, "@nvpm-build", "t")
      if not fn then
        return false, err
      end
      pcall(fn)
    else
      local previous = vim.fn.getcwd()
      ok, detail = pcall(function()
        vim.cmd("cd " .. vim.fn.fnameescape(dir))
        vim.cmd(command)
      end)
      pcall(vim.cmd, "cd " .. vim.fn.fnameescape(previous))
    end
    return ok, detail
  end

  local argv = parse_argv(command)
  if argv and vim.system then
    local result = vim.system(argv, { cwd = dir, text = true }):wait()
    local ok = result.code == 0
    local detail = result.stderr or result.stdout or ("exit " .. tostring(result.code))
    return ok, detail
  end

  local text = type(command) == "table" and table.concat(command, " ") or command
  local cmd = shell_prefix()
  table.insert(cmd, text)
  local previous = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  vim.fn.system(cmd)
  local ok = vim.v.shell_error == 0
  vim.cmd("cd " .. vim.fn.fnameescape(previous))
  return ok, "shell exit " .. tostring(vim.v.shell_error)
end

--- Run build synchronously; returns true on success.
function M.run_sync(plugin)
  if plugin._built or is_build_current(plugin) then
    plugin._built = true
    return true
  end
  if plugin._building then
    return false
  end

  plugin._building = true
  ensure_build_context(plugin)
  local ok, detail = execute_build_sync(plugin)
  plugin._building = false
  if ok then
    plugin._built = true
    write_stamp(plugin)
  else
    util.warn_once(
      "build_fail_" .. plugin.name,
      ("nvpm: build failed for %s: %s"):format(plugin.name, tostring(detail))
    )
  end
  return ok
end

local function execute_build_impl(plugin)
  local build = plugin.spec.build
  local dir = plugin.dir

  if type(build) == "function" then
    local ok, detail = pcall(function()
      local result = build(plugin)
      if type(result) == "table" and type(result.wait) == "function" then
        result:wait()
      end
    end)
    finish_build_safe(plugin, ok, detail)
    return
  end

  local command
  if type(build) == "string" or type(build) == "table" then
    command = build
  elseif build == true then
    command = default_build_command(plugin)
    if not command then
      util.warn_once(
        "build_default_" .. plugin.name,
        ("nvpm: build=true for %s but no build.sh, build.ps1, or Makefile found"):format(plugin.name)
      )
      finish_build_safe(plugin, true)
      return
    end
  else
    util.warn_once(
      "build_type_" .. plugin.name,
      ("nvpm: unsupported build type for %s: %s"):format(plugin.name, type(build))
    )
    finish_build_safe(plugin, false, "unsupported build type")
    return
  end

  if type(command) == "string" and is_ex_command(command) then
    run_ex_command(plugin, dir, command, function(ok, detail)
      finish_build_safe(plugin, ok, detail)
    end)
    return
  end

  local argv = parse_argv(command)
  if argv and vim.system then
    vim.system(argv, { cwd = dir, text = true }, function(result)
      local ok = result.code == 0
      local detail = result.stderr or result.stdout or ("exit " .. tostring(result.code))
      finish_build_safe(plugin, ok, detail)
    end)
    return
  end

  run_shell_command_async(dir, command, function(ok, detail)
    finish_build_safe(plugin, ok, detail)
  end)
end

local function execute_build(plugin)
  ensure_build_context(plugin)
  vim.defer_fn(function()
    execute_build_impl(plugin)
  end, 0)
end

function M._pump_queue()
  vim.schedule(function()
    while active_builds < MAX_CONCURRENT and #build_queue > 0 do
      local plugin = table.remove(build_queue, 1)
      plugin._queued = false
      active_builds = active_builds + 1
      plugin._building = true
      execute_build(plugin)
    end
  end)
end

--- Returns true when the plugin declares a build step.
function M.needs_build(plugin)
  local build = plugin.spec and plugin.spec.build
  return build ~= nil and build ~= false
end

--- Returns true when build finished successfully (this session or stamped).
function M.ready(plugin)
  if plugin._built then
    return true
  end
  if M.needs_build(plugin) and is_build_current(plugin) then
    plugin._built = true
    return true
  end
  return false
end

--- Start a build; calls on_done(ok) when finished.
--- When opts.sync is true, runs inline (lazy.nvim startup parity).
---@param plugin table
---@param on_done fun(ok: boolean)|nil
---@param opts? { sync?: boolean }
function M.start(plugin, on_done, opts)
  opts = opts or {}
  on_done = on_done or function() end

  if plugin._built or is_build_current(plugin) then
    plugin._built = true
    if opts.sync then
      on_done(true)
    else
      vim.schedule(function()
        on_done(true)
      end)
    end
    return
  end

  if plugin._building or plugin._queued then
    plugin._build_waiters = plugin._build_waiters or {}
    table.insert(plugin._build_waiters, on_done)
    return
  end

  local build = plugin.spec.build
  if build == nil or build == false then
    plugin._built = true
    on_done(true)
    return
  end

  local dir = plugin.dir
  if not dir or not util.is_dir(dir) then
    util.warn_once("build_dir_" .. plugin.name, ("nvpm: cannot build %s; plugin directory missing"):format(plugin.name))
    on_done(false)
    return
  end

  if opts.sync then
    notify_building(plugin)
    local ok = M.run_sync(plugin)
    notify_build_result(plugin, ok)
    on_done(ok)
    return
  end

  plugin._build_waiters = plugin._build_waiters or {}
  table.insert(plugin._build_waiters, on_done)

  plugin._queued = true
  table.insert(build_queue, plugin)
  announce_build(plugin)
  M._pump_queue()
end

return M
