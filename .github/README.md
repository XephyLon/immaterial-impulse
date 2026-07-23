<div align="center">
    <img src="assets/immaterial-impulse.png" alt="Immaterial Impulse logo" width="180">
    <h1>【 Immaterial Impulse 】</h1>
    <h3>The evil twin of <a href="https://github.com/end-4/dots-hyprland">illogical-impulse</a>.</h3>
    <p><em>illogical-impulse asks "do you really need this?" — Immaterial Impulse asks "but do you <b>want</b> it?"</em></p>
</div>

---

## The premise

[illogical-impulse](https://github.com/end-4/dots-hyprland) is utility-first: a
disciplined, beautiful, minimal Material 3 shell that earns every widget.

**Immaterial Impulse takes that same gorgeous base and does the opposite.** It
leans all the way into the stuff a utility-first shell calls bloat — live
Wallpaper Engine backgrounds, a full plugin platform, docker controls, Discord
voice, a periodic-table cheatsheet — and ships it as a single, plug-and-play
suite. Same DNA. Zero restraint. On purpose.

It's a fork of illogical-impulse by [@end-4](https://github.com/end-4),
rebranded and unified into one repo: the [Quickshell](https://quickshell.outfoxxed.me/)
shell, the full [Hyprland](https://github.com/hyprwm/hyprland) config, and a
guided installer, together. It **supersedes** an illogical-impulse install —
first launch migrates your old config and secrets over, losing nothing.

> **What it is:** the graphical shell + Hyprland config + installer.
> **What it isn't:** a full system bootstrapper — no drivers, no zram, no bootloader.

---

## The bloat, lovingly curated

### 🧩 A real plugin platform
The headline. Not a config file — an extensible widget platform. Drop a plugin
into `~/.config/immaterial-impulse/plugins/` and it shows up. Two formats:
**declarative** plugins that describe approved components in a `manifest.json`,
and **package** plugins that ship their own QML using native shell components
and tokens. Entry points cover **bar widgets, desktop widgets, control-center
widgets, launcher providers, whole panels, and settings UIs**, behind a
declared **permissions** model (`process`, `network`, `filesystem`, `settings`).
There's a plugin **catalog** with author attribution, **remote install**, and a
design-system library (`ExpressiveTokens`, a component registry) for authors.
Bundled examples: **Docker** controls, **Discord voice**, system monitor,
weather, currency, and clock widgets.

### 🌊 Live wallpapers, not just images
A browser for **local** and **online** wallpapers — plus first-class
**Wallpaper Engine** support: animated WE scenes render live inside the shell,
with **shader transitions** when you switch. The **frost** control decides how
widgets sit over the wallpaper: a true in-shell **blur** of the region behind,
or a cheap palette **tint**.

### 🎨 Material You, everywhere at once
Pick a wallpaper; the whole system re-colors. matugen propagates one palette to
GTK, Hyprland, your terminal, **cava**, **tmux**, and the shell itself.

### 🖥️ A whole desktop, not a bar
Material 3 Expressive throughout: horizontal or vertical **bar**, **dock**,
left/right **sidebars**, an **overview** with live window previews,
**notifications**, **OSD** and **on-screen keyboard**, **media controls with
synced lyrics**, **session/lock** screens, a **polkit** agent, and an in-shell
**Settings app** that configures all of it — one-click Hyprland animation
presets included.

### 🤖 AI + quality-of-life
Chat with any OpenAI-compatible endpoint, Gemini, or local Ollama from the
sidebar. On-screen **translation**, a **region selector** for screenshots and
Google Lens, anti-flashbang, and — yes — a keyboard-shortcut **cheatsheet**
with a periodic table on `Super`+`/`, because why not.

---

## Installation

> Installs the shell to `~/.config/quickshell/ii` and its config to
> `~/.config/immaterial-impulse`. Coming from illogical-impulse? The old
> `~/.config/illogical-impulse` directory and your keyring entries migrate
> automatically on first launch.

```bash
git clone https://github.com/XephyLon/end4-pC.git
cd end4-pC
./setup
```

`./setup` with no arguments opens a **whiptail menu** to pick:

- **Components** — core config and dependencies.
- **Wallpaper Engine** (optional) — builds a custom Quickshell carrying the
  Wallpaper Engine module and puts it ahead of the stock binary on `PATH`. Off
  by default; WE wallpapers degrade to static otherwise.
- **SDDM login theme** (optional, Arch only) — installs
  [ii-sddm-theme](https://github.com/3d3f/ii-sddm-theme) via its own installer,
  matching the lock-screen aesthetic on the login screen. Off by default.
- **Extras** — fontset, fcitx5 IME, and other situational overlays.

Every command prints before it runs. For scripting, `./setup install` runs the
same pipeline non-interactively.

**Keybinds** follow Windows/GNOME muscle memory:

| Keybind | Action |
| --- | --- |
| `Super`+`/` | Full keybind cheatsheet |
| `Super`+`Enter` | Terminal |

---

## Software overview

| Software | Purpose |
| --- | --- |
| [Hyprland](https://github.com/hyprwm/hyprland) | Wayland compositor — manages and renders windows |
| [Quickshell](https://quickshell.outfoxxed.me/) | QtQuick widget system — bar, sidebars, dock, plugins, the lot |
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

The good twin and the community it came from:

- [@end-4](https://github.com/end-4) — illogical-impulse, the root this is
  forked from.
- [pctrade](https://github.com/pctrade/end4-pC) — the `end4-pC` fork this suite
  builds directly on.
- [na-ive](https://github.com/na-ive/nandoroid-shell) — nandoroid-shell, source
  of the bundled Nandoroid widget plugins and expressive design tokens (AGPL-3.0).
- [caelestia-dots](https://github.com/caelestia-dots/caelestia) — the "Caelestia"
  animation preset.
- [@clsty](https://github.com/clsty) — the original install script and much more.
- [@midn8hustlr](https://github.com/midn8hustlr) — the color generation system.
- [@outfoxxed](https://github.com/outfoxxed/) — Quickshell.
- Quickshell dotfiles: [Soramane](https://github.com/caelestia-dots/shell/),
  [FridayFaerie](https://github.com/FridayFaerie/quickshell),
  [nydragon](https://github.com/nydragon/nysh).

## License

See the repository license. Copy and adapt freely — just follow the terms.
