# Common per-widget settings — design

**Status:** landed — see "As it landed" at the end for the three places reality differed
**Scope:** `modules/common/plugins/` (`PluginOptions`, `PluginWidget`, `PluginState`), the bundled
weather and currency manifests, `modules/imi/settings/pages/PluginsPage.qml`

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative.

## Problem

Every desktop widget's settings page opens with the same four rows — **Blur background**, **Lock
position**, **Click through**, **Stay translucent** — synthesized by `PluginOptions.qml` and
concatenated in front of whatever the plugin itself declares. They are host behaviours, not plugin
settings; the manifest only seeds their defaults.

Two more are arriving: a **size** and a **follow parallax** opt-out. Six identical rows in front of
every widget's own two or three options is the bloat this design exists to remove.

There is also a duplicate. Size already exists twice:

- `sizeMode` — a plugin-declared `choice` option on `nandoroid-weather` and `nandoroid-currency`,
  stored at `PluginState.option(id, "sizeMode")`, values `"3x1"`, `"2x1"`, `"2x2"`, `"1x3"`. The
  widget reads it and picks a layout.
- `__gridSize` — host-owned, declared through `manifest.grid.sizes`, driven by the resize handle,
  same `"<cols>x<rows>"` string format.

Two mechanisms, one concept, one format. They must become one before a third widget picks a side.

## Settled input

- Not every widget is resizable. A widget is resizable **only** when it has a design per size —
  currency and weather do, most do not. Offering a size where there is no layout for it is worse
  than offering nothing.
- Presets capture widget sizes, as they already capture positions. Intended.

---

## 1. Two kinds of setting, shown as two kinds

`PluginOptions` stops concatenating. It renders:

1. **The widget's own options** — `manifest.options`, first, because that is what the user opened
   the page for.
2. **A shared section beneath them**, titled "Widget behaviour", holding every host row. It is a
   `ContentSubsection`, so it reads as a group rather than as more of the widget's settings — and,
   per the settings-search contract, its title goes in `searchTerms:`.

Nothing is hidden and no row moves between widgets: the same rows appear for every widget, which is
the point. What changes is that they stop being mistaken for the widget's own settings, and stop
pushing the widget's actual options below the fold.

Rows that cannot apply are omitted rather than disabled — `hasBlurSurface` already does this for
bar-only plugins, and **Size** follows the same rule: absent unless the manifest offers more than
one span. A disabled control that can never enable is noise; the existing greying-out is for rows
that are *temporarily* inert (transparency off), which is a different thing.

## 2. Size, unified

`__gridSize` wins, because it is host-owned and the resize handle needs it. `sizeMode` is retired.

- `nandoroid-weather` and `nandoroid-currency` drop their `sizeMode` option from `manifest.options`
  and declare `grid.sizes` instead, listing the spans they actually have layouts for.
- Their `Widget.qml` reads the resolved span from the host rather than `PluginState.option(id,
  "sizeMode")`. The widget still chooses its own layout from the span — the host owns *which size*,
  the widget owns *what that size looks like*.
- **Migration.** A stored `sizeMode` is read once, mapped to `__gridSize` if it names an offered
  span, and the old key deleted. Without this, upgrading resets both widgets to their default size,
  which is a visible change to a setting the user chose. The migration is keyed by a
  `migratedSizeMode` flag in the same store, matching how `Config.qml` guards its one-shot
  migrations — a stored value beats a default, so a migration that runs twice is not idempotent by
  accident.

The **Size** row in the shared section and the drag handle are two faces of one value. The row is
what makes it discoverable and keyboard-reachable; the handle is what makes it quick.

## 3. Follow parallax

New host row, `followParallax`, default **true**, seeded by `manifest.desktopWidget.followParallax`.

When false, the widget is excluded from the canvas's parallax translation and stays where it was put
relative to the screen.

**This is not a position offset.** The canvas is one item and its `x`/`y` carry the pan, so a widget
opting out must cancel it — `x: -canvas.widgetParallax.x` relative to its own placement, which means
`PluginWidget` needs the canvas's current offset. `AbstractWidget` already finds its canvas
(`findCanvas`), so the value is reachable; the arithmetic belongs in `ParallaxMath` beside
`widgetOffsets` so it is testable.

Note what this does *not* fix: the reachable-area question in
[#154](https://github.com/XephyLon/immaterial-impulse/issues/154). A widget that opts out still has
its drag clamped to the canvas, so it still cannot be dropped in the strip the pan has moved off
screen. Opting out changes where a widget *stays*, not where it may be *placed*. #154's remaining
half — clamping against the screen rather than the canvas — is what fixes placement, and it is
independent of this.

## 4. Where the state lives

All host rows are `pluginOptions` entries, like the four that exist today. Two consequences worth
stating rather than discovering:

- **Presets capture them.** Confirmed intended. A preset therefore carries sizes, parallax opt-outs
  and blur choices, and "Keep settings across presets" is the existing escape hatch.
- **The `__` prefix is reserved** for host state and rejected by `lint_plugin_option_keys.py`, so a
  plugin cannot collide with `__gridSize`. `followParallax` and the four existing rows do **not**
  carry the prefix, which is an inconsistency worth resolving one way or the other. Recommendation:
  leave them unprefixed. The prefix earns its place on `__gridSize` because that key is *not* a row
  a plugin could plausibly declare; the behaviour toggles are. Renaming four live keys would need
  its own migration for no user-visible gain.

## 5. Testing

Testable, and extracted for it:

- The `sizeMode` → `__gridSize` migration: mapping, the not-an-offered-span case, the run-twice case.
  Pure, driven from a QML `TestCase`.
- The parallax cancellation arithmetic, in `ParallaxMath` beside `widgetOffsets`.
- A static check that `PluginOptions` renders the plugin's own options and the shared section as
  separate groups, so a future edit cannot quietly concatenate them again.
- The settings-search index test already added covers the new subsection title automatically.

Not testable, needs the screen: the shared section's appearance and ordering, the Size row agreeing
with the drag handle, and a parallax opt-out actually holding still while workspaces change.

## 6. Landing plan

1. `PluginOptions` splits into the widget's own options and a shared "Widget behaviour" section. No
   new rows — reviewable as a pure presentation change against the four that exist.
2. `followParallax` row + the cancellation in `PluginWidget`, with its `ParallaxMath` helper.
3. Size row, shown only when the manifest offers more than one span.
4. `sizeMode` migration + weather and currency moved onto `grid.sizes`.
5. `docs/widget-grid.md` and AGENT.md.

Step 1 is worth looking at on screen before 2-4 exist, since it changes every widget's settings page
and nothing else.

---

## As it landed

Three places the implementation had to differ from the design above. Recorded here
rather than silently, because each one is a thing the next person would otherwise
re-derive.

1. **A prerequisite bug: `grid.sizes` did not survive the model boundary.** `offeredSizes`
   gated the list on `Array.isArray`, which is false for an array that has crossed a
   `Repeater`'s `model` — and `Background.qml` builds every desktop widget from such a
   model. So a manifest declaring several spans reached the host offering one, and steps
   3 and 4 were both dead on arrival until it was fixed. The runtime harness had missed
   it because it declares its manifests inline on the harness root, a path that never
   crosses a model.

2. **Weather and currency lost their own resize grips, which the design did not mention.**
   Retiring `sizeMode` leaves the host's generic grip in the same bottom-right corner
   their `swap_horiz` chips occupied, so keeping both would stack two controls on one
   spot — and theirs gated on a legacy `cfg.locked` rather than the host's resolved lock,
   staying live on a widget the user had pinned. Their `sizeModeRequested` signal and
   `getModeForWidth` helper went with them.

3. **The migration is scoped by the manifest, not by the key name.** §2 describes reading
   "a stored `sizeMode`", which is not enough: `world-clock` and `calendar` declare no
   `grid` and drive a `sizeMode` of their own from their own toggles, so for them the key
   is a live setting. A pass keyed on the name emptied their options and reset both
   widgets. It now acts only where the manifest offers more than one span. The
   `migratedSizeMode` marker is kept as designed, but is belt-and-braces rather than the
   load-bearing part — deleting the old key is what makes the pass one-shot — and it is
   fired on a settle timer, because a marker records that a pass ran, not that it saw the
   user's data, and manifests load one `FileView` at a time.

The settings-search note in §5 did not apply: this branch's tree has no `searchTerms` in
`SettingsContent.qml` and no `tests/test_settings_search_index.py`.
