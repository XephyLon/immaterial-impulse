# Material 3 & M3 Expressive UI Guidelines

This document establishes the strict rules for developing UI components in `Immaterial Impulse` to ensure they fully conform to the Material 3 (M3) and M3 Expressive design standards. 

These guidelines are **hard constraints** for all future UI work. Ad hoc values ("whatever looks right") are strictly prohibited.

## 1. Design Tokens and Theming

All UI components must exclusively use design tokens defined in `modules/common/Appearance.qml`. Hardcoding colors, radii, font sizes, or animation parameters is strictly forbidden.

### Colors and Layering
The shell uses dynamic, tonal color palettes derived from the wallpaper or theme. 

- **UI Colors (`Appearance.colors`)**: Always use these role-based colors rather than the raw `m3colors` palettes when styling UI surfaces, text, and borders.
  - `colLayer0`: The **outermost** background of a standalone floating surface (e.g., a popup, toast, or OSD with nothing behind it). This token correctly applies `backgroundTransparency` and achieves compositor blur.
  - `colLayer1` through `colLayer4`: Backgrounds for cards or elements **nested inside an already-opaque parent surface** (e.g., a list item inside a sidebar that already has `colLayer0`). These use `contentTransparency`. *Do not use these for standalone popups, as they will render with unblurred transparency.*
- **Text and Icons**: Use `colOnLayer0`, `colOnLayer1`, `colOnSurface`, `colSubtext`, etc., ensuring contrast is maintained across dark/light modes.
- **Primary/Secondary/Tertiary**: Use `colPrimary`, `colSecondary`, `colTertiary` (and their respective `Hover` / `Active` variants) for interactive or accented elements.
### Borders and Outlines
Visible borders are not required for every surface. Many components rely entirely on elevation shadows or tonal contrast (e.g., `GroupedList` relies purely on `colLayer1` against the background without a border). When borders are used, adhere to the following strict conventions:

- **Border Width**: 
  - Use `border.width: Appearance.borderWidth.standard` (1px) for standard structural outlines (e.g., `AboutCard`, `BarIsland`, `StyledPopup`, `StyledSwitch`).
  - Use `border.width: Appearance.borderWidth.emphasis` (2px) to emphasize active/selected states (e.g., `StyledRadioButton`, `ColorSelectionArray`, `GroupButton`, `MonitorRect` when dragged).
  - Use `border.width: Appearance.borderWidth.heavy` (4px) for a deliberately thick accent border (e.g., a clock hand, a strongly-targeted region).
  - Border widths are the one scale not restricted to multiples of 4 - the tokens are `1`, `2`, `4`. *Never* use fractional or ad hoc border widths (e.g., `1.5`), and never re-type `1`/`2`/`4` as a raw number.

- **Border Colors**:
  - `colLayer0Border`: The standard 1px outline for standalone floating surfaces and prominent containers. Often combined with `StyledRectangularShadow` (as seen in `StyledPopup`).
  - `colOutline`: Used for high-contrast interior dividers or form field outlines (e.g., `WindowDialogSeparator`).
  - `colOutlineVariant`: Used for subtle dividers or secondary structural boundaries (e.g., `DockSeparator`, `SecondaryTabBar`).
  - `colError`: Used for semantic error states (e.g., high usage in `ResourceCard`).

- **Combining with Shadows**:
  - Standalone popups and floating elements (like `StyledPopup`, `Toolbar`) combine `StyledRectangularShadow` with a 1px `colLayer0Border` to clearly define edges against complex backgrounds.
  - Interiors and nested menus (e.g., `GroupedList`) drop the border and shadow entirely in favor of tonal contrast (`colLayer1`+).

### Grouped Settings

- Use the standard `GroupedList` presentation when rows are related but remain visually distinct.
- Use `GroupedList { cohesive: true }` when every row belongs to one continuous form or semantic
  unit. Cohesive groups have no gaps or rounded internal seams; only the outside corners are rounded.
- Let `GroupedList` provide the common content inset. Child controls must not add another horizontal
  inset that makes icons, labels, or fields drift out of alignment with adjacent rows.

### Corner Rounding (Radii)
Always use predefined rounding values from `Appearance.rounding`. Never use hardcoded pixel values (e.g., `radius: 12`) or arbitrary maximum values (e.g., `radius: 9999`).

- `unsharpen` (2px) / `unsharpenslight` (4px) / `unsharpenmore` (6px): Extremely subtle rounding for small, nearly square elements.
- `verysmall` (8px): Tooltips, small indicators.
- `small` (12px): Small chips, standard buttons.
- `normal` (17px): Standard cards, list items, menus.
- `large` (23px) / `windowRounding` (18px): Large standalone widgets, floating windows.
- `verylarge` (30px): Prominent dialogs, major distinct UI blocks.
- `full` (9999px): Circular elements, full-bleed pills, FABs.

A radius that is deliberately *computed* from a parent's radius (e.g. a child nested inside a
rounded parent, sized to the parent's radius minus its inset so the corners nest correctly) is not
a violation of this rule - keep the computed expression rather than snapping it to a token.

### Spacing

Always use predefined values from `Appearance.spacing` for `spacing`, `padding`, and margin
properties. Never hardcode pixel gaps (e.g., `spacing: 12`). The canonical Material 3 system scale
is `0, 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 36, 40, 48, 56, 64, 72`, exposed as `space0`,
`space25`, `space50`, `space75`, `space100`, `space125`, `space150`, `space175`, `space200`,
`space250`, `space300`, `space400`, `space450`, `space500`, `space600`, `space700`, `space800`, and
`space900`. `space100` (8px) is the base unit. Prefer multiples of 8 for the main layout rhythm and
the intervening tokens for nested spacing. Snap raw spacing/padding/margin values to this scale.

Use the canonical `spaceNNN` names directly; semantic aliases are intentionally not provided because
they hide the actual spatial relationship. Only genuine large one-off *dimensions* outside the
0-72 range stay literals. Negative offsets use the negated token (for example,
`-Appearance.spacing.space50`).
`tests/lint_spacing.py` (run by `tests/run_tests.sh` / CI) fails on any raw spacing literal in the
token range.

### Dimensions

Element *dimensions* - `implicitWidth`/`implicitHeight`, cell sizes, container heights - are a
different axis from spacing and are deliberately **not** tokenized (there is no natural clustering
to build a scale from, only a long tail of per-widget values). They stay literals, and the lint
does not look at them.

They should still land on the **4dp grid**. When a fixed-height container has to hold
content-sized children, size the children so the total lands on the grid rather than letting the
container grow - see the sidebar's bottom widget group in `AGENT.md`'s design-language section for
a worked example of why growing the container is the expensive choice.

## 2. Motion and Animation

This codebase uses the **M3 Expressive** motion scheme. You must use the component factories in `Appearance.animation` or the explicit curve/duration definitions in `Appearance.animationCurves`. 

Never use raw integer durations (e.g., `duration: 150`), generic QML easing curves (e.g., `Easing.OutCubic`, `Easing.Linear`), or ad hoc bezier curves.

### Spatial Moves (Position and Size)
For elements changing position, dimensions, or layout:
- **Default Spatial Move**: `Appearance.animation.elementMove` (500ms, `expressiveDefaultSpatial`). Use for most spatial transitions.
- **Small Spatial Move**: `Appearance.animation.elementMoveSmall` (350ms, `expressiveFastSpatial`). Use for small adjustments or small elements shifting slightly.

### Effects and State Changes (Color, Opacity)
For color fades, opacities, and non-spatial state transitions:
- **Fast Effects**: `Appearance.animation.elementMoveFast` (200ms, `expressiveEffects`).
- **Faster Effects**: `Appearance.animation.elementMoveFaster` (150ms, `expressiveEffects`). Use for
  the smallest, snappiest state changes where even `elementMoveFast` reads as sluggish.

### Entrance and Exit (Emphasized)
When introducing or removing elements from the screen:
- **Entrance**: `Appearance.animation.elementMoveEnter` (`emphasizedDecel`, 400ms).
- **Exit**: `Appearance.animation.elementMoveExit` (`emphasizedAccel`, 200ms).

### Expandable Content

- Content revealed inside a list must animate into and out of the layout; do not toggle `visible`
  directly and make neighboring rows jump.
- Treat expansion and collapse as spatial motion. Animate the container's height with
  `elementMoveEnter` for expansion and `elementMoveExit` for collapse. The slower decelerating
  entrance gives incoming content time to settle, while the faster accelerating exit removes it
  without making the interface feel blocked.
- Pair the spatial transition with an opacity transition using `elementMoveFast`. Clip the animated
  container so partially revealed controls cannot paint or receive input outside its current bounds.
- Keep the item instantiated until its exit animation reaches zero height; hide it only after (or
  whenever) the animated size is zero.
- Indent expandable child content from the leading edge with an existing spacing token while keeping
  the trailing edge aligned with its parent. This gives nested controls a clear hierarchy without
  unnecessarily reducing their usable width.

### Component Entrance and Exit

- When a standalone component is added to or removed from a surface, combine spatial transformation
  with an effects transition so its origin and destination remain legible. A subtle scale transition
  paired with opacity is appropriate for desktop widgets that appear in place.
- Use `elementMoveEnter` for the entrance and `elementMoveExit` for the exit, and drive opacity with
  the *same* duration and easing curve as the scale, not `elementMoveFast`. Scale and opacity are one
  transition, not two independent ones - if opacity finishes on a different schedule than scale, the
  component visibly reaches full opacity while still growing or shrinking, which reads as a hiccup
  rather than a single cohesive motion. Do not destroy the component as soon as its enabled state
  changes: retain it until the exit transition completes, then deactivate it.
- Animate the component's outer presentation container rather than its content. This keeps entrance
  and exit motion independent from live internal updates and interaction animations such as dragging.

## 3. Existing Nonconformances

The following existing widgets contain hardcoded values that violate these strict guidelines. They have been explicitly identified and should be fixed in future PRs (do not copy their implementation for new widgets):

- **Hardcoded Radii**:
  - `radius: 10` in `TargetRegion.qml` and `IconPickerDialog.qml` - a recurring value with no clean
    fit in the current token scale (equidistant between `unsharpenmore` and `small`).
  - `radius: 1` in `ClippedProgressBar.qml` (progress-bar end caps) and `TodoWidget.qml` (a 1px text
    cursor) - deliberately near-zero on already-tiny elements; snapping to `unsharpen` (2px) would
    double their rounding proportionally, so these are left as literals rather than force-fit.
  - (`CliphistImage.qml`'s `GaussianBlur.radius`, `UserCardWidget.qml`/`WallpaperSelectorContent.qml`'s
    `FastBlur.radius`, `StyledDropShadow.qml`'s `radius`, and `Config.qml`'s lock-screen blur radius
    option are *blur* radii, a different semantic axis from corner rounding, and are not violations.)
- **Hardcoded Colors**:
  - Hex values (e.g., `#ffffff`, `#000000`, `#605790`) in `DashedBorder.qml`, `RoundCorner.qml`, `SineCookie.qml`, and the `shapes/` directory.
- **Inconsistent Borders/Outlines**:
  - `StyledComboBox` uses a floating popup but lacks the standard 1px `colLayer0Border` outline found on `StyledPopup`.
- **Hardcoded Spacing**:
  - Most `spacing`/`padding`/margin literals matching or closely matching an `Appearance.spacing.*`
    value have been migrated. Values outside that scale (`0`, `1`, `7`, `9`, `11`, `13`, `15`,
    `17`-`19`, `>=21`, and negative offsets used for deliberate overlap/bleed effects) are left as
    literals rather than force-fit onto the nearest token - re-evaluate case by case if a widget is
    touched again, rather than bulk-snapping them.
- **Hardcoded Motion**:
  - Ad hoc integer durations with no matching `Appearance.animation.*` value (e.g. `30`, `40`, `50`,
    `80`, `110`, `120`, `180`, `250`, `900`, `1200`, `1400`ms) and arbitrary easing curves (e.g.,
    `Easing.OutCubic`, `Easing.OutQuad`, `Easing.InQuad`) remain across many widgets - the easing
    *curve shape* in particular was deliberately left untouched during the token migration, since
    swapping curve shape (unlike reusing a matching duration number) is visually perceptible and
    wasn't verified against a running compositor. `StyledSwitch.qml` intentionally keeps a custom
    bezier curve (`[0.42, 1.5, 0.28, 0.95, 1, 1]`, durations `320`/`160`) tuned for its snap feel -
    this is a deliberate exception, not an oversight, and should not be folded into
    `Appearance.animation.*`. `MaterialLoadingIndicator.qml`'s 12000ms spinner rotation is
    real-world physical timing, not M3 motion, and is likewise not a violation.
