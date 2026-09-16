# Handoff: the split motion (dynamic island) for the dock, frame mode and imi's motion language

> Committed handoff, 2026-09-17, from the desktop session that shipped PRs #385-#396. Memory is
> machine-local; this file is the channel. Resume on the laptop: start Claude Code **inside the
> repo**, `git pull gh main`, read `AGENT.md` and `CONTRIBUTING.md` in full (hard rules, linted
> citations, receipt-gated PR bodies), then this file, then start at **Task, step 1**. Paths are
> repo-relative; shell paths are under `dots/.config/quickshell/imi/`.

## 1. Where main is (6bcd41a96)

Merged this week, newest first. Each PR body has the design notes.
- **#396** frame mode + dock: band thin on every non-bar edge; a pinned dock meets it as a tab
  (`appearance.frame.dock` "attached", default) or floats a gap above it ("floating"). Bands back
  on the Top layer (on Bottom the wallpaper covered them at cold start), no corner overlap, hidden
  dock no longer leaves a frosted blur silhouette, `qs -c imi ipc call settings page "<id>[:<section>]"`,
  `tests/lint_comment_runs.py`. Reviewer 9.0 / 8.5 / 9.0. Design and mechanism: AGENT.md frame
  point, `docs/proposals/frame-mode.md`, `services/frame_geometry.js`, `modules/imi/dock/dock_geometry.js`.
- **#394** `ConfigLongText` (paragraph row); **#395** Google consent-refusal message.
- **#389-#393** component sweep: `IconButton` (`buttonIcon`, `icon` is FINAL on AbstractButton),
  `CloseButton`, `PopupPlate`, `BarStandalonePill`, `ConfigActionRow`; Material text fields,
  `MaterialPill`, `Fab`, `StyledPopupMenu` and the modes editor's button kit deleted; typing
  settings page on the row grammar. `docs/proposals/component-duplication-census.md` has the
  census; the vendored `modules/common/plugins/designsystem/` mirror (AGPL, imported as
  `Expressive` by six plugin files) is the one open item - a licensing decision for the user.
- **#385-#388** Modes & Routines manager on shell widgets (EditorField/EditorPopup/
  EditorSwitchRow, ConfigSwitch rows, FilterChip days), page transitions, close button.

Open, not for this task: Google sign-in needs a domain for publishing (plan: GitHub Pages user
site `xephylon.github.io` + Search Console); release 1.2.0 not cut (1.1.0 = v1.1.0 on 2088dae22);
the user still has to check #396 live (hover-reveal in frame mode, attached-tab blur parity).

## 2. Rules the desktop session learned (beyond AGENT.md)

- Commits: granular, one logical step each, `git commit -q -F - --only -- <paths>` (`git add -N`
  for new files); no agent attribution anywhere; rebase only, never merge commits; AGENT.md points
  cite `<sha9> ("subject")` - the subject is what survives a rebase (`lint_doc_citations.py`).
- PR body must carry exact receipts: `Docs: updated ...` or `Docs: not needed ...`, and
  `Changelog: updated ...` or `Changelog: not user-visible — ...` (CI-enforced). Merge = local
  fast-forward of main + plain `git push gh main`; `gh pr merge` is not used.
- Suites: one `tests/run_tests.sh` at a time, launched detached (`setsid -f`, SIGINT default -
  a shell `&` or nohup breaks test_screen_record), never edit the tree while it runs, ONE full
  suite per PR once the reviewer passes; small fixes = targeted tests + a nested load. Qt6 QML
  runner is `/usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input <file>`
  with `QT_QPA_PLATFORM=offscreen` (`/usr/bin/qmltestrunner` is Qt5 and exits 1 silently).
- Review loop (mandatory for anything visible): drive in the nested sandbox
  (`tests/sandbox/README.md`), capture EVERY touched surface including the settings row and
  mid-transition frames, dispatch a reviewer subagent that scores perf / look & feel / design
  cohesion 0-10 and lists defects with file:line, iterate until all three >= 8.5. Never capture
  or inject input on the live screen. "Twice means mechanize": a mistake made twice becomes a
  failing check in the same PR.
- Design language: `docs/M3_GUIDELINES.md` - tokens only (`Appearance.rounding/spacing/colors`),
  motion only through `Appearance.animation` tiers taken whole (`lint_motion_tier_partial.py`),
  settings rows on the ContentSection/GroupedList grammar (`test_settings_row_grammar.py`), rows
  come and go via `rowVisible`, ConfigSwitch handlers flip the source, popups are `PopupPlate`,
  one element per purpose (a morph is one travelling element, never crossfading twins),
  `NoticeBox` is for something wrong, not status.
- `pgrep -f` patterns must be bracketed (`run_[t]ests.sh`) because the whole tool command line,
  heredocs included, is what pgrep sees.

## 3. The dock and the frame today (what the motion has to move)

- Geometry: `dock_geometry.js` - `thickness = height + elevation + gap` (75 at defaults), the pill
  is `gap` from the screen edge inside its surface, `exclusiveZone = height + gap` (65),
  `frameOffset(frameOn, attached, band, gap)` = how far the WHOLE SURFACE moves in from the edge in
  frame mode (attached: band - gap = 0 at defaults; floating: band = 5), `cornerRadii(edge, radius,
  attached)` squares the two outward corners when attached.
- `Dock.qml`: `reserves` (pinned, no fullscreen window here) gates the zone and the surface margin
  (`margins { ... dockRoot.frameMargins }` from `DockReservation.frameOffset`); `attached` picks
  the band colour (`FrameGeometry.color`), no border, per-corner radii; the blur region is a
  per-corner `Region` published only while `dockMouseArea.atRest` (the animated centre offsets are
  0). The reveal/hide is `dockMouseArea.anchors.verticalCenterOffset` (horizontal for a vertical
  dock) with `Appearance.animation.elementMoveFast` Behaviors.
- `FrameGeometry.qml` / `frame_geometry.js`: band thickness (gap or `appearance.frame.thickness`),
  `bandMargins(edge)` (horizontal bands span, side bands run between them), `cornerMargins`,
  `color = colBarBackground`, `dockAttached`. `Frame.qml` draws four Top-layer bands, empty input
  mask. `ScreenCorners.qml` draws the fillets at the band.
- **Switching attached <-> floating today is a JUMP**: the layer-shell margin reconfigures the
  surface in one step, the radii, colour and border flip in one frame. That is the seam this task
  turns into a motion.
- Motion tokens: `Appearance.animation.elementMove` (500ms expressiveDefaultSpatial),
  `elementMoveSmall` (350 fast spatial), `elementMoveFast` (200 expressiveEffects),
  `elementMoveFaster` (150), `elementMoveEnter` (400 emphasizedDecel), `elementMoveExit`
  (200 emphasizedAccel); curves in `Appearance.animationCurves`; user multiplier and the
  reduce-motion floor apply to every tier automatically. New motion that needs a new curve adds a
  TIER (and its guideline paragraph), never a literal.

## 4. Task

**Goal.** Make the dock's attached <-> floating switch a *split*: the pill detaches from the
frame's band the way an icon splits from a dynamic island, and docks back into it in reverse.
The motion is derived from a reference, measured, written down as a spec, and becomes the
motion base for frame mode (modals docking into the frame later) and for imi's design language.

**Reference.** https://www.reddit.com/r/unixporn/comments/1wey17r/niri_hope_this_surprises_you_a_little/
(niri, a dynamic-island bar; the moment of interest is an icon/notch element splitting off the
island and merging back). Reddit refuses anonymous fetches of the video (`yt-dlp` says "Account
authentication is required"; the HTML carries no `v.redd.it` link). Try
`yt-dlp --cookies-from-browser <browser> <url>` on a machine with a logged-in browser; if that
fails, ASK THE USER for the video file (share > download in the app) and go on from a path.

**Step 1 - frame analysis.** `ffmpeg -i clip.mp4 -vf fps=60 frames/%04d.png` (or the clip's real
rate), find every split and merge, then for each: contact sheets of the sequence (`magick montage`),
and MEASUREMENTS per frame - island width/height, the child's centre, size and corner radius,
the gap between them, opacity/blur of both, whether the island shrinks before/while/after the
child leaves, whether a neck/bridge (gooey metaball) exists and for how many frames, overshoot,
the total duration and the position/size curves (plot centre-x and width against time; fit a
cubic bezier or read off decel/accel phases). Write it up as `docs/proposals/motion-split.md`:
timeline in ms, the shape grammar (what is one element, what becomes two), the curve(s), and how it
maps onto our tiers (existing tier, or a proposed `Appearance.animation.split*` tier with its
curve and duration, plus the guideline paragraph). Contact sheets may be committed under
`docs/assets/motion/` if small; the frames themselves stay out of the repo.

**Step 2 - the dock split.** Design first (present it, one approach recommended), then build:
- Attach -> float: the tab lifts off the band; as it rises the outward corners round, the border
  and the layer-0 colour come in, the gap opens. Float -> attach: the reverse, ending fused. One
  travelling element - the pill; the band does not move. If the reference shows a neck, decide
  whether a neck is drawn (a small same-colour bridge shape between pill and band during the
  first/last frames) or omitted; say why.
- The hard constraint: the surface's layer-shell margin cannot animate smoothly (it is a
  compositor reconfigure). Options to weigh: (a) keep the surface at its larger extent in frame
  mode and animate the pill's outward margin inside it (mind the hover sliver: an unpinned dock's
  sliver must stay AT the edge; the dock's inner insets assume outward = gap, see #396's review
  for why the surface was moved instead); (b) animate inside the old surface, then reconfigure at
  the end where the pixels already match; (c) something better. Measure, do not guess: the
  reviewer will ask for mid-transition frames.
- Everything through tokens; radii through `cornerRadii` (extend it to interpolate, or animate
  the four radii with the tier); blur region follows (`atRest` semantics: decide whether the
  region rides the animation or lands at the end - per #396 the Region tracks its item's own
  geometry only).
- Tests: extend `tst_dock_geometry.qml` for any new pure arithmetic; `test_frame_mode_contract.py`
  pins; a motion-tier partial take fails `lint_motion_tier_partial.py` (take tiers whole).
- Verification: sandbox capture of BOTH directions as frame sequences (`shot` in a loop at
  ~30 fps is not possible; record with `wf-recorder` inside the sandbox env or capture a dozen
  shots while toggling `appearance.frame.dock` through `apply_overrides.sh`), the settings row,
  pinned and unpinned, default and 14px band, dock on a side edge. Reviewer >= 8.5 on all three.
  One full suite. PR with receipts; update `docs/proposals/frame-mode.md` and AGENT.md's frame
  point (cite the commit).

**Step 3 - write the direction down.** A short section at the end of `motion-split.md`: how the
split generalises - the launcher growing out of the bar, notifications docking into the frame,
the modes flash - so the next slice does not re-derive it.

## 5. Sandbox on the laptop

The tooling is now in the repo: `tests/sandbox/` (README there; the desktop kept a copy in
`~/dev/imi-sandbox-tools/`). It needs a running Hyprland session as the parent, `grim`, `wtype`,
`kitty` or `weston-terminal` for a test window, and Python 3. Overrides for this task, to start
from: `{"config": {"appearance": {"frame": {"enable": true, "dock": "attached"}}, "bar":
{"cornerStyle": 0}, "dock": {"enable": true, "pinnedOnStartup": true}}}`; flip `dock` to
"floating" through `apply_overrides.sh` to trigger the switch while recording.
