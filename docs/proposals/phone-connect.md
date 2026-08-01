# Proposal: Phone Connect (KDE Connect / Valent integration)

> Draft / tracking proposal. Not scheduled.

## Goal

Surface a paired phone inside the shell — battery, notifications, media, file
send, clipboard, find-my-phone — backed by either **KDE Connect** or **Valent**,
whichever the user has installed.

## Current state

Nothing exists. No service, no widget, no quick toggle. This is greenfield.

## Transport constraint (read this first)

**The shell has no D-Bus binding today.** Every service integrates by shelling
out through `Process` — see `services/Brightness.qml:71,90,134` for the pattern.
Both KDE Connect and Valent are D-Bus daemons, so this proposal has to pick a
transport rather than assume one:

- **CLI wrapper** (`kdeconnect-cli`) — matches every existing service, no new
  dependency, but polling-only and awkward for live notification streams.
- **`busctl --json=short` via `Process`** — still shells out, so it fits the
  established pattern, and `busctl monitor` can stream signals rather than
  poll. Structured JSON output parses cleanly.
- **A real D-Bus binding** — cleanest for a notification-mirroring feature, but
  it is a new integration primitive for this codebase and should be justified
  on its own rather than smuggled in with a feature.

Recommendation: `busctl --json` via `Process`, because the interesting features
(notification mirroring, battery updates) are event-driven, and polling them
would be both laggy and wasteful.

## Why

- A phone panel is one of the most-requested desktop-shell features and one of
  the few remaining reasons to keep a separate KDE Connect tray applet running
  alongside the shell.
- Both daemons expose the same conceptual objects (device, battery, notification,
  share, clipboard), so a single abstraction can cover both rather than picking
  a winner and alienating users of the other.
- Valent is the actively maintained GNOME-side implementation; KDE Connect is
  the incumbent. Supporting only one would be a coin flip.

## Approach

- New `services/PhoneConnect.qml`: detects which daemon is running, normalizes
  both onto one device model (`id`, `name`, `type`, `reachable`, `paired`,
  `battery`, `charging`), and exposes actions (`ping`, `ring`, `sendFile`,
  `sendClipboard`).
- Backend detection at startup, with the chosen backend exposed as a read-only
  property so the UI can say which one is in use and degrade honestly when
  neither is installed.
- A right-sidebar surface for device state, plus a quick toggle following the
  existing `modules/common/models/quickToggles/` pattern.
- Notification mirroring routes through the shell's existing notification
  system rather than introducing a parallel one.
- Ship it as a **bundled plugin**, not a hardcoded surface, so users without a
  phone are not carrying a dead widget. This also exercises the plugin API on a
  non-trivial integration.

## Open questions

- Whether pairing should be driveable from the shell or deferred to the
  daemon's own UI. Pairing involves a confirmation on both ends and is
  security-relevant; wrapping it badly is worse than not wrapping it.
- Whether file-send should accept drops onto the drop shelf
  (`modules/imi/dropShelf/`), which already handles mid-drag interaction.

## Out of scope

- Implementing the KDE Connect protocol directly.
- Any feature requiring a companion app change on the phone.
