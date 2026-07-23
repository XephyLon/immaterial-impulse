# Wallpaper Engine Workshop "store" — design draft (PARKED)

> **Status: parked, not scheduled.** This is a draft to preserve the analysis
> and a phased plan for a future in-shell Workshop browser/store in the
> wallpaper picker. Nothing here is built.

## Goal

Let users **discover and install** Wallpaper Engine wallpapers from the Steam
Workshop directly in the shell's wallpaper picker — not just pick from the ones
already downloaded locally. Optionally with filters/sort/playlists parity with
desktop WE managers.

## Current state (what we build on)

- `services/WallpaperEngine.qml` runs `scripts/wallpapers/wallpaper_engine.py`
  over the local WE `libraryPath` (the Steam Workshop content dir for app
  `431960`) and produces `projects` = `{id, path, preview, type, tags, title}`.
- `modules/ii/wallpaperSelector/WallpaperEngineGrid.qml` renders those local
  projects, with free-text **search** and (now) **type filter chips**.
- `OnlineWallpaperGrid.qml` is the existing pattern for a *remote* thumbnail
  grid (fetch previews from a provider, then download a chosen item) — the store
  tab would mirror this shape.

## Two halves — very different cost

### 1. Browse (feasible, no login for browsing)
Query the Steam Workshop for app `431960`:
- **Steam Web API** `IPublishedFileService/QueryFiles` (needs a Web API key) or
  the older `ISteamRemoteStorage/GetPublishedFileDetails`; returns id, title,
  preview image URL, tags, filesize, subscriptions, etc. Alternatively **scrape**
  the public Workshop listing pages (no key, more brittle).
- Implement as a python helper (`scripts/wallpapers/we_workshop.py`, mirroring
  `wallpaper_engine.py`) that emits JSON → feed a new grid tab. Reuse the
  type-filter chips and search from `WallpaperEngineGrid`.

### 2. Download (the blocker — Steam ownership gate)
WE Workshop content (`431960`) is **not anonymously downloadable**. It requires
a Steam account that **owns Wallpaper Engine**. Mechanisms:
- `steamcmd +login <user> +workshop_download_item 431960 <id> +quit` — needs a
  logged-in account owning WE; then move/extract the result into `libraryPath`
  and rescan.
- **Subscribe via the Steam client** (`steam://` protocol / steamworks) — Steam
  then downloads the item to the workshop dir. This is what the reference
  project [jagrat7/linux-wallpaper-engine](https://github.com/jagrat7/linux-wallpaper-engine)
  (Electron + `steamworks.js`) does.

We cannot bypass the ownership requirement from the shell.

## Constraints

- **`web`-type** wallpapers need CEF/Chromium and do **not** render in our
  embedded renderer (the background already falls back to static for them) — the
  store is mainly useful for `scene`/`video` types. Consider hiding/flagging web
  items.
- Steam login/ownership can't be assumed → the download path must be **opt-in
  and gated**, degrading to "browse + open in Steam" when unavailable.
- API key handling / rate limits if using the Web API.

## Proposed phasing

- **P1 — browse-only tab.** New Workshop tab in the wallpaper selector: grid of
  Workshop items (preview, title, tags, type) via the python helper. Each item's
  action is **"Open in Steam"** (`steam://url/CommunityFilePage/<id>`), letting
  the user subscribe there; Steam downloads it; our existing local scan picks it
  up on next refresh. No in-app download, no ownership handling — lowest risk.
- **P2 — in-app install.** Optional, gated behind a "Steam configured + owns WE"
  check: install via `steamcmd +workshop_download_item` (or a subscribe helper),
  extract into `libraryPath`, rescan. Needs config for the steamcmd path /
  Steam auth and clear consent UX.
- **P3 — parity extras.** Sort (subscriptions/date/rating), tag facets,
  playlists — building on the P1 grid.

## Integration points

- New `modules/ii/wallpaperSelector/WorkshopGrid.qml` (mirror `OnlineWallpaperGrid`).
- New `scripts/wallpapers/we_workshop.py` (browse via Web API/scrape → JSON;
  optional download subcommand for P2).
- `Config.options.wallpaperSelector.wallpaperEngine.*` additions: steam auth /
  steamcmd path, Web API key, enable-store toggle.
- Reuse the type-filter chips + search already in `WallpaperEngineGrid`.

## Open questions

- Web API key vs page scraping (key = ToS-clean + stable; scraping = no key but
  brittle).
- How to detect WE ownership before offering in-app download.
- Download consent/UX and where extracted content lands vs Steam's own dir.
- Whether to surface or hide `web`-type items given the renderer limitation.

## Reference

- [jagrat7/linux-wallpaper-engine](https://github.com/jagrat7/linux-wallpaper-engine)
  — Electron manager: Workshop browse + subscribe via `steamworks.js`, filter/
  sort/search, playlists, multi-monitor; requires owning WE on Steam.
