# `nvpm.nvim`

A `lazy.nvim`-compatible Neovim plugin loader for packages installed with [`nvpm`](https://nvpm.dev).

`nvpm` handles **install, update, and lock** (`nvpm-lock.json`).
`nvpm.nvim` handles **runtime loading** from your lazy-style plugin specs.

## Requirements

- Neovim >= 0.10.0
- [`nvpm`](https://github.com/mistweaverco/nvpm-client) CLI

## Install `nvpm.nvim` Itself

```bash
nvpm add --plugin neovim github:mistweaverco/nvpm.nvim
```

If you installed without `--plugin neovim`,
the package may live under `packages/` instead of `plugins/`;
`nvpm.nvim` checks both locations.

## Setup

`nvpm.nvim` is installed under `~/.local/share/nvpm/plugins/`,
which is **not** on Neovim's runtime path by default.

Bootstrap it in **`init.lua`**:

```lua
-- init.lua
local function nvpm_bootstrapper()
  local data = vim.env.NVPM_HOME
  if not data or data == "" then
    data = vim.fs.joinpath(vim.env.HOME, ".local", "share", "nvpm")
  end
  local roots = {
    vim.fs.joinpath(data, "plugins", "github", "mistweaverco_nvpm.nvim"),
    vim.fs.joinpath(data, "packages", "github", "mistweaverco_nvpm.nvim"),
  }
  local bootstrap
  for _, root in ipairs(roots) do
    local path = vim.fs.joinpath(root, "lua", "nvpm", "bootstrap.lua")
    bootstrap = loadfile(path)
    if bootstrap then
      break
    end
  end
  if not bootstrap then
    error("nvpm.nvim is not installed; run: nvpm add --plugin neovim github:mistweaverco/nvpm.nvim", 0)
  end
  return bootstrap({
    ---@type NvpmConfigLsp
    lsp = {
      -- Loads LSP configurations from `vim.fn.stdpath("config")/lsp/*.lua` directory on startup and activates the LSPs on `BufEnter`. Set to `false` to disable.
      loader = true,
    },
    ---@type NvpmConfigTreesitter
    treesitter = {
      -- Loads Tree-sitter parsers from `site/parsers/*.{so,dylib,dll}` on startup. Set to `false` to disable.
      loader = true,
    },
  })
end

nvpm_bootstrapper().setup({
  { "folke/tokyonight.nvim", lazy = false, priority = 1000 },
  { "folke/which-key.nvim", event = "VeryLazy" },
  require("my-plugins.config.kulala-nvim"),
})
```

Install plugins with the CLI first:

```bash
nvpm add github:folke/tokyonight.nvim
nvpm add github:folke/which-key.nvim
nvpm add github:mistweaverco/kulala.nvim
```

## Paths

`nvpm.nvim` resolves paths the same way as [`nvpm-client`](https://github.com/mistweaverco/nvpm-client).

### Environment Overrides


| Variable | Effect |
|----------|--------|
| `NVPM_HOME` | Override **configuration** and **data** roots (lock file, plugins, packages, bin) |
| `NVPM_CACHE` | Override cache root (registry cache, etc.) |
| `XDG_CONFIG_HOME` | Linux/BSD user configuration base (default `~/.config`) |


### Default Locations


| What | Linux | macOS | Windows |
|------|-------|-------|---------|
| Configuration + lock (`nvpm-lock.json`) | `~/.config/nvpm/` | `~/Library/Application Support/nvpm/` | `%APPDATA%\nvpm\` |
| Plugin-installs | `~/.local/share/nvpm/plugins/` | `~/Library/Application Support/nvpm/plugins/` | `%APPDATA%\nvpm\plugins\` |
| Tool packages | `~/.local/share/nvpm/packages/` | `~/Library/Application Support/nvpm/packages/` | `%APPDATA%\nvpm\packages\` |
| CLI binaries | `~/.local/share/nvpm/bin/` | `~/Library/Application Support/nvpm/bin/` | `%APPDATA%\nvpm\bin\` |
| Cache | `~/.cache/nvpm/` | `~/Library/Caches/nvpm/` | `%LOCALAPPDATA%\nvpm\cache\` |


These are separate from Neovim's configuration directory (`~/.config/nvim/` on Linux).

When `NVPM_HOME` is set, both configuration, and data use that single directory (matching the CLI).

## `PATH` For `nvpm` Binaries

`require("nvpm")` prepends the `nvpm` bin directory to `PATH` (same as `nvpm env`).

## Supported `lazy.nvim` Spec Fields


| Field | Supported |
|-------|-----------|
| `[1]`, `url`, `name`, `dir`, `dev` | yes |
| `import`, `dependencies`, `optional`, `specs` | yes - `dependencies` use `lazy.nvim format` (e.g. `"saghen/blink.cmp"`) |
| `enabled`, `cond`, `init`, `opts`, `config`, `main` | yes - `main` optional; inferred like `lazy.nvim` when unambiguous |
| `lazy`, `priority`, `event`, `cmd`, `ft`, `keys` | yes - see [Lazy loading](#lazy-loading) below |
| `module = false` | yes |
| `branch`, `tag`, `commit`, `pin`, `submodules` | install-time only (via `nvpm add`) |
| `build` | yes (`true`, shell string, `argv` table, Ex command starting with `:`, or `fun(plugin)`) - async before first load |
| `version` | ignored when `"*"` (`lazy.nvim` compatibility); otherwise **unsupported** (warn) |
| `checker`, `ui`, `install`, rocks/pkg UI | **unsupported** (warn; use `nvpm` CLI) |


> [!TIP]
> Always use `opts` instead of `config` when possible.
> `config` is almost never needed.

When `opts` is set without `config`,
`nvpm` resolves the main module like [`lazy.nvim`](https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/loader.lua):
scan `lua/` under the plugin directory,
match normalized names, or use the sole top-level module.
If inference fails, set `main` or use a `config()` function.

### Lazy Loading

Same rules as [`lazy.nvim`](https://github.com/folke/lazy.nvim) (`defaults.lazy = false` by default):

A plugin is **lazy** (not loaded at startup) when any of these is true:

- `lazy = true` in the spec
- `defaults.lazy = true` in your `nvpm` setup
- it has `event`, `cmd`, `ft`, or `keys`
- it appears **only** as a `dependencies` entry (not in your top-level spec list)

Otherwise, it is a **start plugin**: loaded synchronously during startup (like `lazy.nvim`).

`dir = ...` (local dev path) does **not** disable lazy loading.
Use `lazy = false` explicitly when a plugin must load at startup
(e.g. session plugins like `kikao.nvim`).

Lazy plugins are added to `'rtp'` and fully loaded on first
`event` / `cmd` / `ft` / `keys` trigger,
or when `require()` resolves one of their modules.

### About The `build` Plugin Spec

`build = true` tries `build.sh`, then `build.ps1` (Windows), then `make`.

Strings starting with `:` are Ex commands (e.g. `:lua require("go.install").update_all_sync()`), matching `lazy.nvim`.

Simple shell commands (e.g. `cargo build --release`) run directly via `vim.system` without a shell when possible.

Build functions run on the main loop; put any `require()` needed before setup inside `build` (same as `lazy.nvim`).

Example:

```lua
build = function()
  pcall(require, "my.plugin.native")
  return require("my.plugin.build").build() -- optional: task with :wait()
end,
```

Non-lazy plugins and require-triggered loads run builds **synchronously** during startup (`lazy.nvim` parity).
Lazy plugins loaded after startup can use the async build queue (max 2 concurrent).
Successful builds are stamped under the `nvpm` cache (`builds/`)
and skipped on later starts until the plugin revision or build command changes.
Plugins with a `build` step only defer `setup()` until `UIEnter` when loaded asynchronously after startup.

### Startup-Performance


`nvpm.nvim` matches `lazy.nvim`'s main startup optimizations by default:


| Option | Default | Effect |
|--------|---------|--------|
| `performance.cache.enabled` | `true` | Enable Neovim's `vim.loader` (bytecode cache + indexed module lookup under `~/.cache/nvim/luac/`) |
| `performance.reset_packpath` | `true` | Set `'packpath'` to `$VIMRUNTIME` only |
| `performance.rtp.reset` | `true` | Slim `'runtimepath'` to configuration, site, `nvpm`, and `$VIMRUNTIME` |
| `performance.rtp.paths` | `{}` | Extra paths to keep on `rtp` when reset is enabled |
| `performance.rtp.disabled_plugins` | `{}` | Skip sourcing these builtin/plugin script `basenames` (e.g. `"gzip"`) |


Cache + `rtp` reset run as soon as bootstrap loads (before `setup({ require(...), ... })` arguments are evaluated),
so plugin spec modules also benefit from `vim.loader`.

Override before bootstrap if needed:

```lua
vim.g.nvpm_performance = {
  cache = { enabled = false },
  reset_packpath = false,
  rtp = { reset = false },
}
```

Or pass `performance` into `setup()` (reapplied when provided).

Bytecode lives in Neovim's cache (`stdpath("cache")/luac`), not under `$NVPM_CACHE`.

### Startup-Profile

After setup, inspect manager timing with:

```vim
:lua require("nvpm.profile").print()
```


Fair A/B against `lazy.nvim` on the same configuration:

```bash
nvim --startuptime /tmp/nvpm.log +q
nvim --startuptime /tmp/lazy.log +q
```

You can _force_ a _rebuild_ by removing the stamp file under
`~/.cache/nvpm/builds/` (or `$NVPM_CACHE/builds/`).

Or by just removing all contents of the build cache directory
(e.g. `rm -rf ~/.cache/nvpm/builds/*`).

## Migration From `lazy.nvim`

### Quick Migrate From `lazy-lock.json`

Helper scripts under [`migration-helpers/neovim/`](migration-helpers/neovim/) install every plugin from your lazy lockfile into nvpm at the **same commits**:

```bash
# Linux / macOS / BSD
chmod +x migration-helpers/neovim/migrate-from-lazy.nvim-package-manager.sh
./migration-helpers/neovim/migrate-from-lazy.nvim-package-manager.sh --dry-run
./migration-helpers/neovim/migrate-from-lazy.nvim-package-manager.sh
```

```powershell
# Windows (PowerShell) - uses built-in ConvertFrom-Json (no Python)
.\migration-helpers\neovim\migrate-from-lazy.nvim-package-manager.ps1 -DryRun
.\migration-helpers\neovim\migrate-from-lazy.nvim-package-manager.ps1
```

```bat
REM Windows (cmd) - launches System32 Windows PowerShell 5.1 (ships with Windows 10+)
migration-helpers\neovim\migrate-from-lazy.nvim-package-manager.bat -DryRun
migration-helpers\neovim\migrate-from-lazy.nvim-package-manager.bat
```

What they do:

1. Ask Neovim for `stdpath("config")` / `stdpath("data")` (respects `NVIM_APPNAME` / `XDG`).
2. Read `lazy-lock.json` (override with `--lockfile` / `-Lockfile`).
3. Resolve `owner/repo` from each plugin’s git remote under the lazy root (override with `--lazy-root` / `-LazyRoot`). The lockfile only stores name + commit.
4. Run:
   `nvpm add --force --plugin neovim github:owner/repo@<commit> …`
   (also `gitlab:`, `codeberg:`, `forgejo:` when the remote host matches).

`lazy.nvim` itself is always skipped.

Plugins must still be present under the lazy root so remotes can be read. Unsupported hosts or missing installs are skipped with a warning.

### Manual Steps

1. Install `nvpm.nvim`: `nvpm add --plugin neovim github:mistweaverco/nvpm.nvim`
2. Replace `require("lazy").setup(...)` in **`init.lua`** with the bootstrap snippet above.
3. Or install plugins individually: `nvpm add --plugin neovim github:owner/repo@<commit>`
4. List plugins: `nvpm ls --only-plugins`.

## Tests

```bash
nvim --headless -l test/spec_test.lua
nvim --headless -l test/main_test.lua
nvim --headless -l test/profile_test.lua
nvim --headless -l test/cache_test.lua
```
