# Expandable panel — design

**Date:** 2026-08-01
**Status:** approved, ready for an implementation plan

## Problem

`docs/M3_GUIDELINES.md` describes an "Expandable Content" contract in seven
parts. Nothing in the shell implements all of it, and every surface that needs
expand/collapse has re-derived its own subset:

| Site | What it does |
| --- | --- |
| `modules/imi/settings/pages/PluginsPage.qml:382` | A hand-rolled `Item` (`optionsRevealer`). The most complete implementation: asymmetric motion, paired opacity, clip, input gating. Misses the leading-edge indent — it insets both sides equally. |
| `modules/common/plugins/bundled/docker/DockerPopup.qml` | Uses the shared `Revealer`. Correct enough to stop rows jumping, but collapse runs the *entrance* curve, nothing fades, and collapsed action buttons stay focusable. |
| `modules/imi/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml` | Its own expansion again. |
| `modules/common/widgets/NotificationGroup.qml` | An elaborate bespoke expansion tied to notification stacking. Out of scope — see below. |

`modules/common/widgets/Revealer.qml` is not the missing component. It is a
25-line GTK-revealer clone that animates `implicitWidth`/`implicitHeight`
between zero and the child's size, with `elementMoveEnter` in **both**
directions and no opacity, indent or input handling. It is also used
**horizontally** (`modules/imi/bar/UtilButtons.qml`'s recording timer,
`SystemIcons.qml`), so it stays exactly as it is. This design adds a component
beside it; it does not replace it.

## The seven rules

Restated from `docs/M3_GUIDELINES.md` because the component is defined by
satisfying them:

1. Animate into and out of the layout — never toggle `visible` and let
   neighbouring rows jump.
2. Height animates with `elementMoveEnter` (400ms `emphasizedDecel`) on
   expansion and `elementMoveExit` (200ms `emphasizedAccel`) on collapse.
3. Opacity transitions alongside it on `elementMoveFast` (200ms
   `expressiveEffects`).
4. The animated container clips.
5. Content stays instantiated until the exit animation reaches zero height.
6. Revealed content is indented from the **leading edge** with a spacing token,
   trailing edge staying aligned with the parent.
7. Collapsed content takes no focus and no input.

Rule 7 is the one every proposal missed and only `PluginsPage` gets right, via
`enabled: expanded`. Rule 6 is the one `PluginsPage` misses.

## Decision

Build **`modules/common/widgets/ExpandablePanel.qml`**: the `PluginsPage` card
generalized. Its fixed behaviour is all seven rules; every visual decoration is
an opt-in property, with defaults that reproduce `PluginsPage` exactly.

Explored and rejected:

- *Motion container only, no card surface.* Cleanly scoped, but the decorations
  the design calls for — outline, shape morph, tonal lift — are properties of
  the **card**, not of the revealing region. A container-only component cannot
  own them, and every adopter would hand-roll the card around it, which is the
  duplication being removed.
- *Card with a built-in chevron trigger.* Fewer lines for Docker and Bluetooth
  rows, but unusable for `PluginsPage`, whose trigger is the plugin's enable
  switch, and for `SettingsContent`, whose trigger is nav-rail state. The
  trigger stays outside the component; `expanded` is driven by the call site.

## API

```qml
ExpandablePanel {
    // Required. Driven by the call site - a chevron button, a ConfigSwitch,
    // any other state. The component never toggles it itself.
    property bool expanded: false

    // Header slot. Always visible; the call site puts its own row here,
    // including whatever control drives `expanded`.
    property alias header: headerRow.data

    // Revealed content. Default property, so children land here.
    default property alias content: contentColumn.data

    // ── Decorations, all off-by-default except `divider` ──
    property bool outline: false      // 1px colOutlineVariant, colPrimary while open
    property bool divider: true       // hairline rule between header and content
    property bool shapeMorph: false   // radius normal -> large while open
    property bool tonalLift: false    // surface steps up one layer while open
    property int  staggerStep: 0      // >0 staggers content children, ms apart

    // Surface layer for the card itself; adopters nest at different depths.
    property int contentLayer: StyledRectangle.ContentLayer.Pane
}
```

`staggerStep` is an int rather than a bool so the call site sets the interval it
wants; `0` disables. When staggering, the first child is held back by a fixed
**120ms lead-in** so the container is visibly open before content arrives, and
collapse runs all children out together — a staggered exit keeps painting into a
container that is already closing.

## Anatomy and tokens

```
StyledRectangle            contentLayer (default Pane / colLayer1)
                           radius rounding.normal, -> rounding.large when shapeMorph && expanded
                           border 0, or borderWidth.standard when outline
                             colOutlineVariant closed -> colPrimary open
  ColumnLayout  spacing 0
    RowLayout   header     margins spacing.space100
    Rectangle   divider    1px colOutlineVariant, margins space100,
                           opacity 0 -> 1 on elementMoveFast
    Item        panel      clip: true
                           enabled: expanded
                           visible: expanded || implicitHeight > 0
                           implicitHeight: expanded ? content.implicitHeight : 0
                           leftMargin  spacing.space300   <- rule 6, leading only
                           rightMargin spacing.space100   <- trailing stays aligned
                           bottomMargin expanded ? space50 : 0
      ColumnLayout content
```

Every value is an existing token. No new tokens are introduced.

## Motion

| Property | Expanding | Collapsing |
| --- | --- | --- |
| `implicitHeight` | 400ms `emphasizedDecel` | 200ms `emphasizedAccel` |
| `opacity` | 200ms `expressiveEffects` | 200ms `expressiveEffects` |
| divider `opacity` | 200ms `expressiveEffects` | 200ms `expressiveEffects` |
| `radius` (shapeMorph) | 350ms `expressiveFastSpatial` | 350ms `expressiveFastSpatial` |
| surface (tonalLift) | 200ms `expressiveEffects` | 200ms `expressiveEffects` |
| children (staggerStep) | 120ms lead-in, then `staggerStep` apart | all together, no delay |

## Adopters

Migration order, each its own commit:

1. **`PluginsPage.qml`** first. Its decorations are the component's defaults —
   no outline, rule on, nothing else — so it is the smallest possible first
   migration and the safest way to prove the component before anything else
   depends on it.

   It is **not** pixel-identical, and that is intended: `PluginsPage` currently
   fails rule 6, insetting both sides by `space100`, so adopting the component
   moves its option rows from a `space100` leading inset to `space300`. Note
   that its content is a `GroupedList`, which pads its own rows by a further
   `space100` — so the visible left inset goes from 16px to 32px while the right
   stays at 16px. Confirm that against the live shell before moving on; if it
   reads as too deep in practice, the fix is to reconsider the token in the
   component, not to reintroduce a symmetric inset.
2. **`DockerPopup.qml`** — replaces the `Revealer` in `Card`. Sets
   `outline: true` and `contentLayer: Subgroup` to keep its current look, and
   gains input gating, the correct exit curve and the indent. It also turns
   **`staggerStep` on**: the container cards are where the staggered reveal is
   wanted, so this migration is what proves that trait rather than leaving it
   theoretical.

   Pick the interval against the live shell during the migration. The design
   study is the evidence to weigh: a container card carries five action
   buttons, so at 120ms the last one lands 600ms after the header moves —
   longer than the container's own 400ms opening. 40ms and 80ms both keep the
   tail inside the opening; the fixed 120ms lead-in is separate and does not
   change.
3. **`BluetoothDeviceItem.qml`** — evaluate during implementation; migrate only
   if it maps cleanly.

Explicitly **not** adopters:

- `NotificationGroup.qml`. Its expansion is entangled with stack collapsing,
  per-item peek heights and a `StyledListView`. Forcing it through this
  component would distort both.
- `Revealer.qml` call sites that reveal horizontally.
- `SettingsContent.qml`'s nav-rail sections — a `Revealer` with an ad hoc
  opacity binding, which this component's card shape does not fit.

## Why the traits are options, not YAGNI

`CONTRIBUTING.md` warns against generalized plumbing beyond what was asked, and
five optional traits would be exactly that for a component with three internal
call sites. That is not what this is. **The traits exist for plugin authors.**

The component ships as part of the plugin-facing surface: bundled plugins
already `import qs.modules.common.widgets` (seven times across the current
bundle), and `docs/PLUGIN_DESIGN_SYSTEM.md` explicitly permits plugins to use
existing shell components alongside `ExpressiveTokens`. A plugin author building
a settings surface or a popup needs an expansion that is correct by default and
can be dressed to match their widget — without copying the motion contract into
their own QML and getting the exit curve wrong, which is precisely what the
in-tree code has been doing.

Two consequences follow, and both are binding:

- **The property names are a compatibility surface.** Once third-party plugins
  bind `outline`, `divider`, `shapeMorph`, `tonalLift` and `staggerStep`,
  renaming them breaks installed plugins. Get the names right in the first
  commit; treat later changes the way any public API change is treated.
- **It has to be documented, not just exist.** `docs/PLUGINS.md` gains an entry
  covering the component, its properties and the fact that `expanded` is driven
  by the call site. An undocumented plugin-facing widget is one nobody uses,
  and the duplication continues.

The "delete it if unused internally" instinct does not apply here: internal
adoption is not the measure.

## Deliverables

1. `modules/common/widgets/ExpandablePanel.qml`.
2. Its contract test and runtime harness (below).
3. A `docs/PLUGINS.md` entry documenting it as a plugin-facing component.
4. The `PluginsPage` and `DockerPopup` migrations, one commit each.
5. A `docs/M3_GUIDELINES.md` note pointing the Expandable Content section at the
   component, so the next widget author reaches for it instead of re-deriving
   the rules a fifth time.

## Verification

`tests/run_tests.sh` instantiates pure-logic singletons and never builds
widgets, so it cannot catch a component that fails to compile. Therefore:

- A structural contract test pinning the seven rules in the component source —
  in particular that collapse uses `elementMoveExit`, that `enabled` tracks
  `expanded`, and that the leading and trailing margins differ.
- A `qs -p` runtime harness in the repo's existing style (see
  `DockerRuntimeTest.qml`) that builds the panel, expands it, and asserts the
  height actually changes — the pattern that caught the Docker popup's real
  behaviour where greppable tests could not.
- Live verification against the running shell after each migration, per
  `CONTRIBUTING.md`.

## Reference

Interactive study of all eight treatments, on this machine's live palette and
the real curves: <https://claude.ai/code/artifact/6476d3ff-3c20-4f50-8f7a-f6c9bcb9e3f5>
