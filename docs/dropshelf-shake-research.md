# Research: shake-to-summon DropShelf while dragging files

Feature idea: a user picks up files in a file explorer (Dolphin, Nautilus,
Thunar), shakes the cursor mid-drag, and the DropShelf appears under the
cursor to receive the drop — the macOS **Dropover** interaction, on Hyprland.

Verdict up front: **plausible, with one honest limitation** — on Wayland the
shell cannot know a drag is in progress until the cursor is over one of its
own surfaces, so the shake gesture must be armed *all the time* (mitigated by
a strict gesture heuristic), or the trigger must be a drag-over-shell-surface
instead of a shake. Both designs are cheap; they compose well.

## What exists today

- `modules/ii/dropover/DropShelfPanel.qml`: an Overlay-layer PanelWindow at
  `GlobalStates.dropShelfX/Y`, holding a `DropArea { keys: ["text/uri-list"] }`
  that accepts `drop.urls` into the `DropShelf` service. Items on the shelf are
  re-draggable out (`Drag.mimeData` with `text/uri-list`).
- Opened today only explicitly: the desktop right-click menu sets
  `dropShelfX/Y` from the click position and flips `GlobalStates.dropShelfOpen`.
- So the *receiving* side of the feature is done and file-explorer-compatible;
  the research question is purely about the *summoning* gesture.

## The Wayland constraint (the crux)

`wl_data_device` delivers drag events (`enter`/`motion`/`leave`/`drop`) only
to the surface currently under the cursor. There is **no global "a drag is
happening" signal** for uninvolved clients, and Hyprland's IPC exposes
nothing about DND either (checked: no drag/dnd query or event; `hyprctl`
knows `cursorpos` and nothing pointer-state related beyond it). macOS
Dropover can watch the global drag pasteboard; a Wayland client cannot.

Consequences:

1. The shell cannot arm shake detection "only while dragging".
2. The shell *can* detect a drag the moment the cursor crosses any of its
   surfaces (a `DropArea.entered` fires on drag-hover without a drop) — the
   bar already spans the full top edge on every monitor.

## Design A — cursor-shake, always armed

- **Cursor tracking:** poll Hyprland's request socket with `cursorpos` from
  one persistent helper (or a QML Timer + persistent socket via a tiny
  long-running process). Measured on this machine: **0.03 ms per query** over
  the raw socket — 60 Hz polling is negligible. Do NOT fork `hyprctl` per
  poll (that's a process spawn per frame).
- **Gesture:** classic shake heuristic — within a sliding ~600–800 ms window,
  ≥ 3 horizontal direction reversals, each leg ≥ ~60 px, net displacement
  small. Tunable thresholds; strict defaults make accidental triggers rare.
- **Action:** open the shelf at the cursor (`dropShelfX/Y` = last position),
  auto-dismiss after ~5 s if nothing was dropped and the pointer never
  entered it. If the user was mid-drag, the newly mapped shelf receives the
  drag's `enter` as soon as the cursor moves over it, and the existing
  DropArea takes the drop.
- **Risks:**
  - False positives while not dragging. Mitigations: strict thresholds,
    auto-dismiss, suppress while a fullscreen client is focused
    (`HyprlandData.focusedMonitorHasFullscreen`), config toggle (default off
    or on — user's call).
  - **Needs a 5-minute manual test:** Hyprland must re-evaluate DND focus
    onto a layer surface that maps *mid-drag*. Expected to work (DND focus
    follows motion), but verify before building the gesture; if it fails,
    only Design B works.
  - Polling runs whenever the feature is enabled. At 60 Hz over the raw
    socket the cost is noise, but gate it: no polling while locked or while
    a fullscreen app runs.

## Design B — drag-over-bar reveal (the Wayland-native variant)

Put a passive `DropArea { keys: ["text/uri-list"] }` on the existing bar
window (and/or a screen-corner hot zone). `onEntered` (drag-hover, no drop
needed) → open the shelf near the cursor. This is 100 % reliable — the shell
*knows* a file drag is happening because the drag entered its surface — with
zero polling, zero heuristics, zero false positives, and no new input
interception (the bar already owns that strip of screen).

UX: "drag files to the bar and the shelf pops out" — discoverable and
deliberate; the shelf can highlight while the drag hovers it. This is the
same reachability trick Windows/KDE users know from drag-to-taskbar.

## Recommendation

Ship **B first** (small, deterministic, no daemons), then add **A** behind a
config toggle (`dropShelf.shakeToSummon`) for the true Dropover feel, after
the mid-drag-mapping test passes. Both funnel into the existing
`dropShelfOpen/X/Y` plumbing, so neither touches the shelf itself.

Rough sizing: B ≈ one DropArea + open/dismiss logic (a day including
polish); A ≈ a cursor-poll service + gesture detector + tests (2–3 days,
dominated by threshold tuning).

## Compatibility notes

- Dolphin/Nautilus/Thunar/PCManFM all offer `text/uri-list` on file drags —
  the existing shelf DropArea already accepts exactly that; multi-selection
  arrives as a multi-line uri-list. Chromium/Firefox downloads drags also
  carry uri-list (bonus).
- Drops both ways already work today (shelf accepts and re-offers items), so
  explorer compatibility is entirely about the summon gesture, not the data
  path.
- Niri/non-Hyprland: Design B is compositor-agnostic; Design A's cursor
  polling is Hyprland-specific (would need a per-compositor backend).
