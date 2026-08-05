# Reactive greeter sync — design

**Status:** approved (option A staged now; option B is a separate future proposal)
**Repos:** immaterial-impulse (hub), imi-sddm-theme (satellite)

## Problem

The SDDM greeter's inputs — the generated `Settings.qml`, `Colors.qml`, and the wallpaper
file — are refreshed only as a **side effect of color generation**: matugen's
`iisddmtheme` post_hook runs `generate_settings.py && sudo …/sddm-theme-apply.sh`.
The trigger is "matugen ran," not "an input the greeter consumes changed." Two defect
classes follow, both observed in production:

1. **Staleness.** Any config change that affects `Settings.qml` without changing colors
   never propagates: WE scaling (reported by the user against imi-sddm-theme#13's
   subject matter), clock style, lock blur, panel family, quote text. The greeter
   drifts from the desktop until the next wallpaper/color event.
2. **The still race.** On a scene switch, matugen fires immediately, but the
   full-resolution still is grabbed off the live surface ~1s after it settles
   (`Background.captureGreeterStill`). The root copy can run before the still exists,
   so the greeter keeps the preview until the *next* color event. The imperative chain
   cannot express "wait for the still."

## The framing

The shell is already an observer system — QML property bindings are the Observable
pattern natively. The greeter pipeline is the one consumer wired as a callback of an
unrelated event instead of an observer of its own inputs. The design choice is only
*where the observer lives* and *what a firing costs*.

## Options considered

**A. Shell-side observer + user-side diff gate (chosen, staged now).**
A `GreeterSync` service singleton observes the greeter-relevant leaves
(`wallpaperEngine.{activeProject,activePath,activeType,activePreview,scaling}`,
`background.wallpaperPath`) and is poked explicitly by `captureGreeterStill` after a
successful still write — the grab completion becomes an observed event, which closes
the race. Debounced (~1.5s), it runs a satellite-owned sync wrapper:
`generate_settings.py` → hash the greeter-consumed outputs (Settings.qml, Colors.qml,
the derived still's identity) → compare to the last-applied stamp → `sudo apply` only
on change. The diff gate is what makes observation cheap to be generous with: an
over-observed leaf costs a hash, not a root copy. matugen's post_hook keeps firing the
same wrapper — it *is* the correct observer for "colors changed."

**B. Root out of the hot path (endgame; separate proposal).**
Install-time: an sddm-readable staging dir (`/var/lib/imi-sddm-theme`, user:sddm);
theme resolves Settings/Colors/conf/wallpaper from it. Updates become atomic
user-space writes; the NOPASSWD rule leaves the hot path (install/uninstall only).
Trust is a wash: root already copies the user's generated QML into the pre-auth
greeter verbatim, single-user assumption already baked in. Not bundled here because it
touches install/uninstall/check and login-critical pathing — the class
imi-sddm-theme's AGENTS.md opens with. Needs its own spec.

**C. systemd user `.path` units** watching config.json + the stills dir. Works with
the shell stopped, closes the race externally, systemd serializes for free. Passed
over for now: duplicates the shell's knowledge outside it and still runs root per
change; composes with B later if wanted.

## Decision

Stage A now. B later as its own proposal. #13 (the scaling mapping) is orthogonal —
required under every option; reactivity only governs when it refreshes.

## Contracts introduced by A

- **Hub → satellite:** the hub only ever invokes
  `~/.config/imi-sddm-theme/sddm-theme-sync.sh` (absent = silent no-op, so the hub
  works on machines without the theme). It never calls the root apply script directly.
- **Satellite:** the wrapper owns generation, gating, and the privileged call. The
  matugen post_hook calls the same wrapper. Nothing else calls `sudo` for the theme.
- **Race closure:** any code that produces a greeter-consumed artifact asynchronously
  (today: the still grab) must poke `GreeterSync.request()` on completion.
- **Reactive rule (enforced in AGENT.md):** "when X changes, refresh Y" features must
  observe X — a binding, a `Connections`, an explicit completion poke — never
  piggyback on an unrelated trigger because it happens to fire often enough.
