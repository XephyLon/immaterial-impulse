<div align="center">
    <img src="assets/immaterial-impulse.svg" alt="Immaterial Impulse logo" width="180">
    <h1>【 Immaterial Impulse 】</h1>
    <h3>A Material 3 Expressive desktop suite for Hyprland, built on Quickshell.</h3>
    <p>Shell, Hyprland config, and a guided installer in one repo — install it and go.</p>
</div>

---

## Overview

Immaterial Impulse is a complete, plug-and-play Linux desktop suite. It bundles a
custom [Quickshell](https://quickshell.outfoxxed.me/) graphical shell, a full
[Hyprland](https://github.com/hyprwm/hyprland) configuration, and a menu-driven
installer that wires everything up across Arch, Fedora, Gentoo, and Nix.

It is a fork of [illogical-impulse](https://github.com/end-4/dots-hyprland) by
[@end-4](https://github.com/end-4), rebranded and unified into a single
self-contained project. It **supersedes** an illogical-impulse install rather
than sitting beside it — a first run migrates your old config and secrets over,
losing nothing.

> **What this is:** the graphical shell + Hyprland config + installer.
> **What this isn't:** a full system bootstrapper — it won't set up graphics
> drivers, zram, or your bootloader.

---

## Features

### The shell — Material 3 Expressive, everywhere
A cohesive Quickshell interface with a horizontal or vertical **bar**, a
**dock**, left and right **sidebars**, an **overview** with live window
previews, **notifications**, **on-screen display** and **on-screen keyboard**,
**media controls with synced lyrics**, a **session/lock screen**, a **polkit**
agent, and an in-shell **Settings app** that configures all of it — including
one-click Hyprland animation presets.

### Material You theming from your wallpaper
Pick a wallpaper and the whole system re-colors. Colors are generated with
matugen and propagated to GTK, Hyprland, your terminal, **cava**, **tmux**, and
the shell itself — one palette, everywhere.

### Wallpapers, including live Wallpaper Engine
A built-in browser for **local** and **online** wallpapers, plus first-class
**Wallpaper Engine** support: animated WE scenes render live inside the shell,
with **shader-based transitions** when you switch between them. Choose how
widgets sit over the wallpaper with the **frost** control — a true in-shell
**blur** of the region behind, or a cheap palette **tint**.

### AI, in the sidebar
Chat with multiple providers — any OpenAI-compatible endpoint, Google Gemini,
local Ollama, and more — without leaving your desktop.

### Quality of life
On-screen **screen translation**, a **region selector** for screenshots and
Google Lens lookups, anti-flashbang, and a custom lock screen with consistent
widget frost (or optional hyprlock).

---

## Installation

> Immaterial Impulse installs the shell to `~/.config/quickshell/ii` and its
> config to `~/.config/immaterial-impulse`. If you're coming from
> illogical-impulse, the old `~/.config/illogical-impulse` directory and your
> keyring entries are migrated automatically on first launch.

Clone the repo and run the installer:

```bash
git clone https://github.com/XephyLon/end4-pC.git
cd end4-pC
./setup
```

Running `./setup` with no arguments opens a **whiptail menu** where you pick:

- **Components** — core config and dependencies.
- **Wallpaper Engine** (optional) — builds a custom Quickshell carrying the
  Wallpaper Engine module and puts it ahead of the stock binary on `PATH`.
  Off by default; WE wallpapers gracefully fall back to static otherwise.
- **Extras** — fontset, fcitx5 IME, and other situational overlays.

Every command is printed before it runs. For scripting, `./setup install` runs
the same pipeline non-interactively.

**Keybinds** follow Windows/GNOME muscle memory. A few to start with:

| Keybind | Action |
| --- | --- |
| `Super`+`/` | Full keybind list |
| `Super`+`Enter` | Terminal |

---

## Software overview

| Software | Purpose |
| --- | --- |
| [Hyprland](https://github.com/hyprwm/hyprland) | Wayland compositor — manages and renders windows |
| [Quickshell](https://quickshell.outfoxxed.me/) | QtQuick widget system — bar, sidebars, dock, and the rest of the shell |
| matugen | Material You color generation from the wallpaper |
| Others | See [deps-info.md](../sdata/deps-info.md) |

---

## Screenshots

| Lyrics | Online wallpapers |
|:---:|:---:|
| ![Lyrics](../dots/.config/quickshell/ii/screenshots/1.png) | ![Online wallpapers](../dots/.config/quickshell/ii/screenshots/2.png) |
| Desktop widgets | Hyprland config |
| ![Desktop widgets](../dots/.config/quickshell/ii/screenshots/5.png) | ![Hyprland config](../dots/.config/quickshell/ii/screenshots/6.png) |
| Configurable bar | And more |
| ![Configurable bar](../dots/.config/quickshell/ii/screenshots/3.png) | ![And more](../dots/.config/quickshell/ii/screenshots/4.png) |

---

## Credits

Immaterial Impulse stands on the work of the illogical-impulse project and its
community:

- [@end-4](https://github.com/end-4) — illogical-impulse, the upstream this
  suite is forked from.
- [@clsty](https://github.com/clsty) — the original install script and much more.
- [@midn8hustlr](https://github.com/midn8hustlr) — the color generation system.
- [@outfoxxed](https://github.com/outfoxxed/) — Quickshell.
- Quickshell dotfiles: [Soramane](https://github.com/caelestia-dots/shell/),
  [FridayFaerie](https://github.com/FridayFaerie/quickshell),
  [nydragon](https://github.com/nydragon/nysh).

## License

See the repository license. Feel free to copy and adapt — just follow the terms.
