



<div align="center">

# 💠 end4-pC

**A personal fork of [illogical-impulse](https://github.com/end-4/dots-hyprland) by [@end-4](https://github.com/end-4)**  
Customized and maintained by **pctrade**

</div>

---

## 🎬 Showcase

<p align="center">
  <a href="https://www.youtube.com/watch?v=o0Vsh7eVchs">
    <img src="https://img.youtube.com/vi/o0Vsh7eVchs/maxresdefault.jpg" alt="Material 3 Expressive x Linux" width="85%" style="border-radius: 12px; box-shadow: 0px 10px 30px rgba(0,0,0,0.5);"/>
  </a>
</p>

</div>

---

## 📸 Screenshots
<div align="center">

| 🎵 Lyrics | 🖼️ Online Wallpapers |
|:---:|:---:|
| ![Screenshot 1](screenshots/1.png) | ![Screenshot 2](screenshots/2.png) |
| 🪟 Desktop Widgets | 🔧 Hyprland Configs |
| ![Screenshot 5](screenshots/5.png) | ![Screenshot 6](screenshots/6.png) |
| ⚙️ Configurable Bar | ✨ And More |
| ![Screenshot 3](screenshots/3.png) | ![Screenshot 4](screenshots/4.png) |

</div>

---

## ⚡ Installation

> [!NOTE]
> This fork manages its own configuration folder independently — it does **not** overwrite or modify any existing setup. However, it does require [illogical-impulse](https://github.com/end-4/dots-hyprland) to be installed and running.

```bash
cd ~/.config/quickshell/
git clone https://github.com/pctrade/end4-pC.git
killall qs 2>/dev/null; qs -c ii > /dev/null 2>&1 & disown
```

### 🔧 Set as your default shell (optional)

If you like it and want it to load by default instead of `ii`, edit:

```bash
~/.config/hypr/hyprland/variables.lua
```

And change this line:

```lua
hl.env("qsConfig", "ii")
```

to:

```lua
hl.env("qsConfig", "ii")
```

> [!TIP]
> After saving, restart Hyprland or run `hyprctl reload` to apply the change.

---

### ⚙️ Settings keybind

To open the settings panel, add this to your Hyprland config:

```lua
hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
```

> **Note:** Settings is an overlay panel, not a regular window — `Super + Q` won't close it. Use the same keybind to toggle it or press `Escape`.

## 🧩 Plugins

The shell supports declarative manifests and installable QML plugin packages. See
[PLUGINS.md](PLUGINS.md) for entry points, remote installation, permissions, and lifecycle safety.

## 🖼️ Wallpaper Engine

The Wallpaper Selector can browse installed Steam Wallpaper Engine Workshop
projects and apply them through
[`linux-wallpaperengine`](https://github.com/Almamu/linux-wallpaperengine). It
automatically discovers Steam library folders and exposes project search, FPS,
scaling, audio, refresh, and stop controls. Install `linux-wallpaperengine`,
open the selector, and choose **Wallpaper Engine** from the source menu.

The selected project's preview is passed through the existing Material color
pipeline, and the live wallpaper is restored by the same Hyprland restore hook
used for video wallpapers.

Because a live wallpaper renders on its own surface that the shell cannot sample,
applying one also renders a full-scene still at monitor resolution (cached per
project under the cache directory). Lock/unlock and switches between live
wallpapers peel that still with the configured wallpaper-change animation, so the
transition stays sharp and correctly framed instead of using the tiny Workshop
preview. A still is a frozen frame; if a scene changes, use the re-render button
in the Wallpaper Engine toolbar to refresh it. Rendering a still needs
`linux-wallpaperengine`'s `--screenshot` support.

## 🙏 Credits

Huge thanks to the people who made this possible:

- **[@end-4](https://github.com/end-4)** — for creating the original [dots-hyprland](https://github.com/end-4/dots-hyprland) / illogical-impulse shell. An absolute masterpiece of a dotfiles project 🫡
- **[@gh0stzk](https://github.com/gh0stzk)** — for providing the weather API integration that made the weather widget possible 🙌
- **[@StarS2112](https://github.com/StarS2112)** — for showcasing this fork 🙌

---

<div align="center">

Made with ❤️ — feel free to fork and make it your own

</div>
