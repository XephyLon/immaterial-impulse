# Proposal: Clight integration

> Implemented on PR #66: `services/Clight.qml` (busctl transport, two-staged
> feature detection), backlight deferral in `services/Brightness.qml`, a
> colour-temperature OSD indicator, and a daemon-gated Clight section on the
> Services settings page. The daemon-absent path is stock behaviour, verified
> end to end by `tests/test_clight_integration_runtime.py`. Night-light
> ownership deliberately stays with `services/Hyprsunset.qml` - the settings
> section warns about a temperature fight instead of silently resolving it.

## Goal

Let the shell cooperate with **Clight** — ambient-light-driven brightness, screen
colour temperature, and dimming — instead of fighting it, and expose its state
and controls in the settings UI.

## Current state

- `services/Brightness.qml` owns brightness with two backends: DDC/CI for
  external monitors (`ddcMonitors`, `ddcDetectFinished()`) and the kernel
  backlight otherwise. It exposes `increaseBrightness()` /
  `decreaseBrightness()` and a per-screen `BrightnessMonitor` component.
- There is no colour-temperature control anywhere in the shell.
- There is no ambient-light handling, and no awareness of Clight.

## The conflict

Clight and `Brightness.qml` both write the same backlight. If Clight is
running, the shell's brightness changes get silently reverted the next time
Clight recalculates from the ambient sensor, and the shell's OSD shows a value
that is about to stop being true. Today this presents to the user as
"brightness keeps jumping back".

That conflict is the real reason to do this work; the colour-temperature
feature is a bonus.

## Transport constraint

**The shell has no D-Bus binding today** — every service shells out via
`Process` (see `services/Brightness.qml:71,90,134`). Clight is a D-Bus daemon
(`org.clight.clight`). The consistent option is `busctl --json=short` through
`Process`, which also allows `busctl monitor` for state changes rather than
polling. Introducing a real D-Bus binding would be cleaner but should be
justified on its own merits, not as a side effect of this proposal.

## Why

- The current behaviour is a bug from the user's perspective, and it only
  affects users who installed Clight deliberately — i.e. users who care.
- Colour temperature is a common request and Clight already implements it well,
  including geoclue-based sunset/sunrise. Reimplementing that in the shell would
  be strictly worse.
- Clight is optional and not widely installed, so this must degrade to exactly
  today's behaviour when it is absent.

## Approach

- New `services/Clight.qml`: detects whether the daemon is present and running,
  exposes its state (current backlight target, temperature, ambient reading,
  whether it is in auto mode), and wraps its controls.
- Teach `services/Brightness.qml` to defer: when Clight is active, brightness
  changes go through Clight (so it does not immediately revert them) rather than
  writing the backlight directly. When Clight is absent, behaviour is unchanged.
- Add a Clight section to the settings UI, visible only when the daemon is
  detected — auto/manual toggle, temperature range, and a live ambient reading.
- Add a colour-temperature control to the existing brightness OSD when Clight is
  available.

## Open questions

- Whether the shell should offer to install Clight, or only integrate when the
  user has already chosen it. Leaning toward the latter: it needs a sensor or
  webcam to be useful, and a broken auto-brightness is worse than none.
- Whether `wlsunset`/`gammastep` users deserve the same deference treatment for
  temperature. They do not conflict with brightness, so this is a smaller and
  separate question.

## Out of scope

- Implementing ambient-light sensing in the shell.
- Bundling or auto-installing Clight.
