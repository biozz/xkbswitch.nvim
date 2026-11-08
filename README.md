# xkbswitch.nvim

Automatically use English in Normal/Visual mode and restore your previous layout
when entering Insert mode or leaving Neovim. Supports macOS and existing Linux
xkb-switch/g3kb-switch installations.

## macOS: automatic installation

Requires Neovim 0.10+, macOS 11+, and internet access on the first launch.
Apple Silicon and Intel are supported by the same universal binary package.
`curl`, `tar`, and `shasum` are supplied by macOS. No Homebrew, compiler, CMake,
or administrator access is needed on the target machine.

With lazy.nvim:

```lua
{
  "biozz/xkbswitch.nvim",
  lazy = false,
  opts = {},
}
```

Or call `require("xkbswitch").setup()` with another plugin manager.

On first setup the plugin asynchronously downloads the pinned native release,
checks its SHA-256 against that release's `SHA256SUMS`, and atomically installs it
under `stdpath("data")/xkbswitch/native-v0.1.1/`. The package includes `bin/issw`,
`lib/libInputSourceSwitcher.dylib`, and the upstream MIT license. Layout switching
starts in the same session once installation and layout discovery finish.
Until then Neovim works normally, without automatic switching.

Subsequent startups reuse that version without network requests. Plugin updates
only download again when the pinned native version changes. Concurrent Neovim
processes use separate temporary directories and never expose partial packages.
An interrupted process can leave a `.tmp-*` sibling directory; it is not reused
and may safely be removed once that process exits.

Download failures disable switching for that session with a warning.
`:XkbSwitchInstall` retries setup and installation. `:checkhealth xkbswitch`
reports the active library, installation directory, and errors. A corrupt
installed package can be repaired by closing Neovim, deleting the version's
managed directory, and starting Neovim again.

## Options

```lua
require("xkbswitch").setup({
  auto_install = true, -- default on macOS; managed package takes precedence
  -- normal_layout = "com.apple.keylayout.ABC", -- optional explicit override
  -- user_layouts = { "com.apple.keylayout.ABC", "your.other.layout" },
  -- events_get_focus = { "FocusGained", "CmdlineLeave" },
})
```

By default `issw -l` discovers available layouts. ABC and U.S. are both recognized
as English. Set `normal_layout` for another preferred Normal-mode layout.
`user_layouts` bypasses discovery; it does not install macOS keyboard layouts.
Custom layouts still need to be installed and enabled in macOS.

For an existing manually installed library:

```lua
require("xkbswitch").setup({
  xkb_switch_lib = "/your/path/libInputSourceSwitcher.dylib",
  switcher_command = "/your/path/issw", -- only needed for layout discovery
})
```

An explicit library always takes precedence and disables automatic downloading.
With `auto_install = false`, macOS searches `/opt/homebrew/lib`, `/usr/local/lib`,
and `/usr/lib` for the library, and uses `issw` on PATH to discover layouts.
You can also provide `user_layouts` to avoid needing the CLI.

## Linux

Automatic binary installation is currently macOS-only. Install
[xkb-switch](https://github.com/grwlf/xkb-switch) or
[g3kb-switch](https://github.com/lyokha/g3kb-switch) and its GNOME extension through
your existing system setup, then call `setup()`. Explicit `xkb_switch_lib`,
`switcher_command`, and `user_layouts` remain supported.

## Tmux

Enable focus notifications in `.tmux.conf`:

```tmux
set -g focus-events on
```

## Native releases and development

`scripts/build-native.sh` builds a pinned revision of
[vovkasm/input-source-switcher](https://github.com/vovkasm/input-source-switcher)
for arm64 and x86_64, targets macOS 11, applies ad-hoc signatures, and packages
both components with relative library loading. Building requires Apple's
Command Line Tools and CMake 3.28+; these are release-maintainer requirements.

```sh
./scripts/build-native.sh
./tests/run.sh
```

Tests use an isolated data directory, simulated network failures, and the real
packaged CLI/library. They do not change your active keyboard layout.

The `Native macOS release` workflow builds and publishes assets for `native-v*`
tags. For a new native version, change `M.version` in `install.lua`, update this
README, commit, and push the matching tag. Never replace an existing version's
assets: the plugin trusts the checksum supplied by the pinned GitHub release.
The plugin lockfile pins the Lua code and thus its selected native version.

The Lua plugin is GPL-3.0; the separately built upstream dependency is MIT.
