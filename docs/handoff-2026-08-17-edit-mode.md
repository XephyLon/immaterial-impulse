# Handoff — Edit Mode, remaining stages

Written 2026-08-17 from the desktop session. Everything below is on `gh/main`;
the suite is **939 passed, 0 failed** there. Read this, then dispatch agents.

## What is already done

Edit Mode stages 1–4 have landed and are deployed on the desktop machine:

| PR | What |
|---|---|
| #233 | `layout_ops.js` + the four reorder call sites; swap became move |
| #236 | The viewport: `GlobalStates.editMode`, the shrink, the exit ladder |
| #239 | `EditModeCard.qml` — corner, shadow, the lattice's edge fades |
| #240 | The chrome surface: toolbar, Done, tab bar (`quickshell:editMode`) |
| #241 | Grid appears on drag, not on entry; the glass edge; the clipping fix |
| #243 | The `GroupedList` plate hole; chrome insets derived from bar/dock |
| #244 | The edge cut from a 5px ring to a 1px catch |

The design spec is `docs/superpowers/specs/2026-08-16-edit-mode-design.md` and it
is the authority. §12 is the landing plan. Read it in full before dispatching
anything — it was rewritten around the maintainer's own model and several of its
sections supersede what earlier notes said.

## The remaining stages, in order

**Stage 5 — the drawer, and add-at-pointer.** The one that makes the
maintainer's sketch real. The drawer's width becomes the inset's input; opening
it *translates* the desktop (it must never resize it — a viewport that changes
size mid-edit rescales every widget under the cursor); a widget dropped from it
lands at the pointer. `PluginManager.availablePlugins` feeds it.
`lint_edit_mode_scope.py` lands here with the allowlist it will police, and
`WidgetsSubmenu` is removed in its own commit.

Note `EditModeInsets` (added in #243) is already the one derivation both
surfaces read, and the reserved width is already in the geometry — stage 5 spends
it rather than inventing it.

**Stage 6 — per-widget context menu and the Size stepper.** Right-click a widget
opens Remove / Pin / Size instead of toggling the global lock. Size indexes
`offeredGridSizes`; `Tension.stepSize` already exists and is tested
(`PluginWidget.qml:331`). §5 of the spec is the rule and the calendar widget is
the documented exception — it declares no `grid` on purpose so the host cannot
overwrite the size its own handles chose.

**Stage 7 — promote the `BarWidgets` catalogue** out of `BarConfig.qml:49-71`.
Ships as a move; `BarConfig` reads the singleton and looks identical.

**Stage 8 — the bar and the dock, edited in place at full size.** They are not
scaled and not tabs; that is the maintainer's decision. Auto-hide suspended by
adding a term to `mustShow`, widgets inert, remove badges, `ReorderDragArea`
across the three buckets, visible bucket boundaries, add from `BarWidgets` and
`DesktopEntries`. Two orientations and two content trees: a fix applied to one is
invisible in the other, so test both.

**Stage 9 — the Lockscreen tab.** Do the `LockSurface.interactive` refactor and
the preview context **first, as their own commit with no editing in it** — that
is the stage that most wants a careful review and it should not be carrying a
feature. Then the tab. One open question the spec deliberately leaves open, and
the maintainer has not answered it: whether island *contents* are reorderable or
only their visibility. Visibility needs no new storage; contents needs three
ordered lists in `Config.options.lock` and a data-driven rewrite of
`LockSurface.qml:236-501`. **Ask before building the larger one.**

**Stage 10 — edge snap and hysteresis, then undo.** Edge snap is arithmetic plus
a `tst_*`. Undo is last because it depends on probe 4, which was only partially
answered: a `Bottom`-layer surface with `keyboardFocus: OnDemand` does grant QML
active focus (measured), but whether the compositor delivers keys was never
established — that needs a nested session to test safely. Do not design keyboard
interaction on the strength of the partial result.

## Also queued, outside Edit Mode

- ~~**The 40 partial tier takes.**~~ Done. `tests/lint_motion_tier_partial.py`
  (#242) registered 40 animations across 17 files that named a tier's `duration`
  and dropped its curve, so they ran on `Easing.Linear`. All 40 were taken whole
  and the register is empty; see AGENT.md's design-language section for how the
  tiers were decided and for the two things measured on the way (an
  `Easing.BezierSpline` with no `bezierCurve` is Linear and the lint cannot see
  it; `alwaysRunToEnd` is inert inside a `Behavior`).
- **Motion survey items not yet done**: #2 single-scalar driver, #3 the keyed
  quick-toggle model (the survey's strongest recommendation; #233 was shaped to
  keep it open), #6 FLIP reposition, #7 rounding scale knob, #11 `SpringAnimation`,
  #12–15. See `docs/p3drovfx-animation-research-2026-08-16.md`.
- **#200 steps 2–3**: `lint_test_isolation.py` (removes the "exit the user's
  session" hazard — `run_notification_blur_probe.sh:114` runs a bare
  `hyprctl dispatch exit`), and wiring in the tests nothing runs
  (`sdata/tests/*.py`, `WidgetGripLockRuntimeTest.qml`).
- **A dangling symlink**: `tests/imports/qs/services/Docker.qml`. The
  `tests/imports/` mirror surfaces a missing target as `Type X unavailable` with
  the real cause on the last `caused by` line.
- **Wallpaper Engine clock depth** — designed, not built. See PR #234's §8: the
  stills are already the viewport's own size so a mask registers 1:1, the key
  cannot be the still's stat triple (re-grabbed per load, so acceptance would be
  lost every restart) and needs `--identity we:<projectId>`, and the layer must
  mask the live surface rather than the still.

## Rules that are not negotiable

Read `AGENT.md` and `CONTRIBUTING.md` in full first, every agent, every time.
Granular commits explaining WHY. **No agent attribution** in commits or PR
bodies. PR bodies end with a `Docs:` receipt. **Rebase only** — never a merge
commit. Every new check proven to fail on deliberately planted broken code, in a
clean tree.

## Lessons this repo paid for, worth passing to every agent

- **A survey claim about our own tree is not evidence.** Three were wrong the
  same way — their side read, ours searched. Open our file and cite a line.
- **`pkill -x quickshell` is unsafe here.** `qs -p` harnesses share the process
  name, and one agent left a second shell running for 38 minutes. Kill the
  primary by pid.
- **Never a bare `hyprctl`.** It resolves its target from
  `HYPRLAND_INSTANCE_SIGNATURE` alone and reaches the user's real session.
- **Synthetic pointer input is not evidence.** Use it to set up a state, then
  judge from a screenshot or a readback.
- **A measurement needs a control.** Two captures separated in time on a live
  desktop are not an A/B; a crop cannot tell you whether a thing is centred.
- **Weston harnesses die with `The Wayland connection broke` under contention.**
  That is contention, not failure. Re-run in isolation; never report a contended
  run as a result.
- **Three defensible tones on one edge sum to a border.** Score the whole
  perimeter, not one tone at a time.
