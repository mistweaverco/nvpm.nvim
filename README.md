<div align="center">

![NVPM Logo](assets/logo.svg)

# nvpm.nvim

[![Made with love](assets/badge-made-with-love.svg)](https://github.com/mistweaverco/nvpm.nvim/graphs/contributors)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/mistweaverco/nvpm.nvim?style=for-the-badge)](https://github.com/mistweaverco/nvpm.nvim/releases/latest)
[![Discord](assets/badge-discord.svg)](https://nvpm.dev)

[Requirements](#requirements) • [Install](#install) • [Documentation](https://nvpm.dev/neovim)

<p></p>

A thin layer to use [packages](https://github.com/mistweaverco/nvpm-registry)
installed via [NVPM](https://github.com/mistweaverco/nvpm-client) in Neovim.

You only need this, if you don't want to have your `PATH` modified by sourcing `nvpm env`.

<p></p>

</div>

## Requirements

- Neovim 0.10.0+

## Install

Via [lazy.nvim](https://github.com/folke/lazy.nvim):

### Configuration

```lua
{ 'mistweaverco/nvpm.nvim', opts = {} },
```

> `opts` needs to be an empty table.
