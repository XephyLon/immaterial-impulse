#!/usr/bin/env bash

# Resolve script directory to allow running from anywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# The Python contract checks resolve source files relative to the repository
# root, so make the suite independent of the caller's working directory.
cd "$PROJECT_ROOT" || exit 1

# The QML tests instantiate pure-logic singletons and never render anything, but
# qmltestrunner still builds a QGuiApplication and aborts with SIGABRT (exit 134)
# if Qt cannot resolve a platform plugin - which is what happens over SSH, in a
# container, or in any session without a display. CI already sets this; default
# it here too so running the suite directly behaves the same everywhere. An
# explicit value still wins, for anyone who needs a real platform plugin.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

# Find Qt6 qmltestrunner
QMLTESTRUNNER=""
POSSIBLE_PATHS=(
    "/usr/lib/qt6/bin/qmltestrunner"
    "/usr/lib64/qt6/bin/qmltestrunner"
    "/usr/lib/x86_64-linux-gnu/qt6/bin/qmltestrunner"
    "qmltestrunner-qt6"
    "qmltestrunner6"
    "qmltestrunner"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [[ -x "$path" ]]; then
        QMLTESTRUNNER="$path"
        break
    elif which "$path" &>/dev/null; then
        QMLTESTRUNNER="$(which "$path")"
        break
    fi
done

if [[ -z "$QMLTESTRUNNER" ]]; then
    echo "Error: qmltestrunner not found. Please install Qt6 Declarative Test package." >&2
    exit 1
fi

echo "Using test runner: $QMLTESTRUNNER"
echo "Running QML unit test suite..."

# Static lint: catch Appearance.* usage missing its qs.modules.common import
# before running the QML tests (this class of bug pegs the shell at 100% CPU).
echo "Running QML import lint..."
if ! "$SCRIPT_DIR/lint_qml_imports.sh"; then
    echo "Import lint failed."
    exit 1
fi

# Static lint: a directory reached by a relative QML directory import is read as
# a module name by Quickshell's scanner, so it cannot contain hyphens.
echo "Running QML module directory lint..."
if ! python3 "$SCRIPT_DIR/lint_qml_module_dirs.py"; then
    echo "QML module directory lint failed."
    exit 1
fi

echo "Running system tray icon lint..."
if ! bash "$SCRIPT_DIR/lint_systray_icon_binding.sh"; then
    echo "System tray icon lint failed."
    exit 1
fi

echo "Running lockscreen theme lint..."
if ! bash "$SCRIPT_DIR/lint_lockscreen_theme.sh"; then
    echo "Lockscreen theme lint failed."
    exit 1
fi

echo "Running region selector capture lint..."
if ! bash "$SCRIPT_DIR/lint_region_selector_capture.sh"; then
    echo "Region selector capture lint failed."
    exit 1
fi

# Static lint: spacing/padding/margin must use Appearance.spacing tokens, not
# raw pixel literals in the token range.
echo "Running Material icon lint..."
if ! python3 "$SCRIPT_DIR/lint_material_icons.py"; then
    echo "Material icon lint failed."
    exit 1
fi

echo "Running spacing token lint..."
if ! python3 "$SCRIPT_DIR/lint_spacing.py"; then
    echo "Spacing lint failed."
    exit 1
fi

# Static lint: an Appearance token a QML file reads must be declared. An
# undeclared one is `undefined`, which renders 0 after a single warning - or
# NaN, with no warning at all, where the call site does arithmetic on it.
echo "Running Appearance token lint..."
if ! python3 "$SCRIPT_DIR/lint_appearance_tokens.py"; then
    echo "Appearance token lint failed."
    exit 1
fi

echo "Running disabled-opacity lint..."
if ! python3 "$SCRIPT_DIR/lint_disabled_opacity.py"; then
    echo "Disabled-opacity lint failed."
    exit 1
fi

# Static lint: the same rule for the interaction model's transform. A scale
# composites exactly the way an opacity does, and the lint above recognises a
# doubled dim by its opacity EXPRESSION - so the doubled scale discordVoice
# shipped was invisible to it for the whole life of the widget.
echo "Running interaction-motion lint..."
if ! python3 "$SCRIPT_DIR/lint_interaction_motion_double.py"; then
    echo "Interaction-motion lint failed."
    exit 1
fi

# Static lint: an animation that names a motion tier's duration must take that
# tier's easing with it. Leaving the curve behind hands the animation Qt's
# default, Easing.Linear - the generic curve M3_GUIDELINES §2 forbids - and
# nothing about the source or the log shows it. Two fixes in two days each
# repaired the sites someone had noticed and left more in the same file.
# Static lint: every mirror symlink under tests/imports resolves. A link there
# outlives a deleted target silently - nothing fails until a test imports that
# exact type, which for an untested singleton is never.
# Contract: one logical-pixel multiplier, reading 1, with the reason attached.
# It looks like dead compatibility plumbing and is not - 629 sites read it and
# it multiplies the widget grid - so both "delete it" and "make it a zoom knob"
# are mistakes this pins the shape against.
echo "Running effective scale contract tests..."
if ! python3 "$SCRIPT_DIR/test_effective_scale_contract.py"; then
    echo "Effective scale contract tests failed."
    exit 1
fi

# Static lint: every workflow job declares a timeout. A job with no ceiling
# runs until GitHub's six-hour limit when a step wedges, holding the only
# runner while every other PR queues behind it - measured on the 0.27.0
# release run, which spent six hours inside apt.
# The one thing in this shell that reads every key on the machine: what it
# emits (keycodes, never characters), what it keeps (nothing), and when it is
# allowed to run at all (only while the on-screen keyboard is open).
# Static lint: a harness that launches qs brings its own compositor. Without
# it, `qs -p` maps on the session's display and a suite run opens and closes
# real windows over whatever the user is doing - and a layer surface there
# covers their screen outright.
echo "Running display isolation lint..."
if ! python3 "$SCRIPT_DIR/lint_display_isolation.py"; then
    echo "Display isolation lint failed."
    exit 1
fi

echo "Running key monitor tests..."
if ! python3 "$SCRIPT_DIR/test_key_monitor.py"; then
    echo "Key monitor tests failed."
    exit 1
fi

echo "Running workflow timeout lint..."
if ! python3 "$SCRIPT_DIR/lint_workflow_timeouts.py"; then
    echo "Workflow timeout lint failed."
    exit 1
fi

echo "Running test import symlink lint..."
if ! python3 "$SCRIPT_DIR/lint_test_import_symlinks.py"; then
    echo "Test import symlink lint failed."
    exit 1
fi

echo "Running motion tier lint..."
if ! python3 "$SCRIPT_DIR/lint_motion_tier_partial.py"; then
    echo "Motion tier lint failed."
    exit 1
fi

# Static lint: a duration read out of animationCurves is the tier's BASE, so
# the speed multiplier and the reduce-motion floor never reach it. Eight sites
# and one hand-copied tier were doing that, invisibly - the sibling lint above
# passes them, because they name tokens and pair with the right curve.
echo "Running motion multiplier bypass lint..."
if ! python3 "$SCRIPT_DIR/lint_motion_multiplier_bypass.py"; then
    echo "Motion multiplier bypass lint failed."
    exit 1
fi

# Static lint: one desktop-widget base class. The design system arrived with a
# dead copy that nothing imported and that still carried a drag idiom d2ebb5aeb
# removed - unreachable, three fixes behind, and the richer-looking of the two.
echo "Running stale widget canvas lint..."
if ! python3 "$SCRIPT_DIR/lint_no_stale_widget_canvas.py"; then
    echo "Stale widget canvas lint failed."
    exit 1
fi

# Static lint: a drag that reorders a list reorders it through layout_ops.js.
# Four surfaces had written that out for themselves and two of the four
# exchanged the two entries instead of moving one - the same list for a step of
# one and a different list for anything longer, which is why nobody saw it.
echo "Running reorder-arithmetic lint..."
if ! python3 "$SCRIPT_DIR/lint_reorder_arithmetic.py"; then
    echo "Reorder-arithmetic lint failed."
    exit 1
fi

# Static lint: a bar widget that answers a primary click says so with the
# pointer. The shared button types always did; every hand-written MouseArea in
# the bar forgot separately.
echo "Running clickable-cursor lint..."
if ! python3 "$SCRIPT_DIR/lint_clickable_cursor.py"; then
    echo "Clickable-cursor lint failed."
    exit 1
fi

# Static lint: a ConfigSwitch click is an intent. Assigning to `checked` - in
# the widget or at a call site - destroys the binding every settings page hangs
# on it, and the switch silently detaches from the config it is showing.
echo "Running ConfigSwitch intent lint..."
if ! python3 "$SCRIPT_DIR/lint_config_switch_intent.py"; then
    echo "ConfigSwitch intent lint failed."
    exit 1
fi

echo "Running shell name lint..."
if ! python3 "$SCRIPT_DIR/lint_shell_name.py"; then
    echo "Shell name lint failed."
    exit 1
fi

echo "Running duplicate import lint..."
if ! python3 "$SCRIPT_DIR/lint_duplicate_imports.py"; then
    echo "Duplicate import lint failed."
    exit 1
fi

echo "Running qmldir registration lint..."
if ! python3 "$SCRIPT_DIR/lint_qmldir_registration.py"; then
    echo "qmldir registration lint failed."
    exit 1
fi

echo "Running shader path lint..."
if ! python3 "$SCRIPT_DIR/lint_shader_paths.py"; then
    echo "Shader path lint failed."
    exit 1
fi

echo "Running widget card tint lint..."
if ! python3 "$SCRIPT_DIR/lint_widget_card_tint.py"; then
    echo "Widget card tint lint failed."
    exit 1
fi

echo "Running cava claim lint..."
if ! python3 "$SCRIPT_DIR/lint_cava_claims.py"; then
    echo "cava claim lint failed."
    exit 1
fi

echo "Running process pattern lint..."
if ! python3 "$SCRIPT_DIR/lint_self_matching_process_patterns.py"; then
    echo "Process pattern lint failed."
    exit 1
fi

# A harness that launches qs on the inherited session bus measures the
# developer's session as much as this tree: the lock island reorder test read
# the maintainer's browser as an MPRIS player, which hides the two slots it
# drags, and failed on their machine while passing everywhere else.
echo "Running runtime bus isolation lint..."
if ! python3 "$SCRIPT_DIR/lint_runtime_bus_isolation.py"; then
    echo "Runtime bus isolation lint failed."
    exit 1
fi

echo "Running doc citation lint..."
if ! python3 "$SCRIPT_DIR/lint_doc_citations.py"; then
    echo "Doc citation lint failed."
    exit 1
fi

# The `Changelog:` PR-body receipt, testable without pushing. CHANGELOG.md's
# [Unreleased] section was empty at two consecutive releases, so both rebuilt
# it from the git log; changelog_receipt.py is the rule and this drives it over
# in-memory PR fixtures. The CI half runs the same module rather than carrying
# a second copy of its pattern.
echo "Running changelog receipt tests..."
if ! python3 "$SCRIPT_DIR/test_changelog_receipt.py"; then
    echo "Changelog receipt tests failed."
    exit 1
fi

# Static lint: a manifest's option keys and the host's own per-plugin state
# share one PluginState namespace, so the `__` prefix is the host's alone.
echo "Running plugin option key lint..."
if ! python3 "$SCRIPT_DIR/lint_plugin_option_keys.py"; then
    echo "Plugin option key lint failed."
    exit 1
fi

echo "Running plugin process lifecycle lint..."
if ! python3 "$SCRIPT_DIR/lint_plugin_processes.py"; then
    echo "Plugin process lifecycle lint failed."
    exit 1
fi

# Static lint: a body-scoped blur region and its `blur = false` layer rule live
# in two different files, and either half alone renders wrong without erroring.
echo "Running blur region pairing lint..."
if ! python3 "$SCRIPT_DIR/lint_blur_region_pairing.py"; then
    echo "Blur region pairing lint failed."
    exit 1
fi

# Static lint: a Behavior whose duration/easing branch on the same flag whose
# change handler writes the animated property. The animation latches its tier
# when it starts and nothing orders the binding update first, so a close can run
# the entrance curve - visible only frame by frame.
echo "Running behavior tier race lint..."
if ! python3 "$SCRIPT_DIR/lint_behavior_tier_race.py"; then
    echo "Behavior tier race lint failed."
    exit 1
fi

# Static lint: a handler that writes an animated property and then defers a
# second write to it has written a start value the retarget swallows, so the
# animation runs from its destination to its destination. Measured, that is why
# the wallpaper selector's entrance never animated once: 99.6% of its travel
# landed in a single frame.
echo "Running animated start-write lint..."
if ! python3 "$SCRIPT_DIR/lint_animated_start_write.py"; then
    echo "Animated start-write lint failed."
    exit 1
fi

# Static lint: a toolbar title written as an icon beside a label IS
# IconAndTextToolbarButton's construction, so it renders as an unfilled button.
# Nothing errors and no frame comparison can see it; it is only wrong to a
# person deciding what to click.
echo "Running toolbar title lint..."
if ! python3 "$SCRIPT_DIR/lint_toolbar_title_is_not_a_button.py"; then
    echo "Toolbar title lint failed."
    exit 1
fi

# Static lint: Edit Mode's chrome band is asymmetric, so a piece still centred
# in it with `/ 2`, or a call site that forgets `bandFraction` and takes the
# 0.5 default, renders off its gap without erroring.
echo "Running edit mode band fraction lint..."
if ! python3 "$SCRIPT_DIR/lint_edit_mode_band_fraction.py"; then
    echo "Edit mode band fraction lint failed."
    exit 1
fi

# Static lint: a window's clear colour must be a literal. One that reaches alpha
# 255 makes Qt declare the Wayland surface opaque, and nothing ever retracts
# that, so the window loses its compositor blur for the rest of the process.
echo "Running window clear colour lint..."
if ! python3 "$SCRIPT_DIR/lint_window_clear_color.py"; then
    echo "Window clear colour lint failed."
    exit 1
fi

# Static lint: the bar popup overlay's layer surface must keep constant
# geometry. A bound margin or implicit size there reconfigures the surface on
# every frame of a morph, which is the create-map-destroy loop the design exists
# to avoid; its mask also cannot follow a transform.
echo "Running bar popup overlay lint..."
if ! python3 "$SCRIPT_DIR/lint_bar_popup_overlay_static.py"; then
    echo "Bar popup overlay lint failed."
    exit 1
fi

# Static lint: StyledText must default to PlainText and every rich-text opt-in
# must be reviewed - manifest strings are attacker-controlled and the render
# site is their only defence.
echo "Running rich text opt-in lint..."
if ! python3 "$SCRIPT_DIR/lint_rich_text_optin.py"; then
    echo "Rich text opt-in lint failed."
    exit 1
fi

# The one marquee in the shell is an infinite animation sitting on a label, so
# WHERE it may run is as much of the contract as how it runs: the gate has to
# ask whether the text overflows as well as whether it is on screen, the travel
# is scaled by the motion policy and the dwell deliberately is not, and every
# adoption is reviewed against a surface that is hidden when idle.
echo "Running marquee text contract tests..."
if ! python3 "$SCRIPT_DIR/test_marquee_text_contract.py"; then
    echo "Marquee text contract tests failed."
    exit 1
fi

# The shell has two password prompts - the lock screen and the polkit dialog -
# and they were two different text fields, one of them Material's outlined
# container with the prompt floating in a notch. The check derives the control
# from the LOCK screen rather than naming a type, so the two cannot drift. It
# also holds the dialog to exactly one filled button, the confirming one.
echo "Running polkit dialog contract tests..."
if ! python3 "$SCRIPT_DIR/test_polkit_dialog_contract.py"; then
    echo "Polkit dialog contract tests failed."
    exit 1
fi

echo "Running expandable panel contract tests..."
if ! python3 "$SCRIPT_DIR/test_expandable_panel.py"; then
    echo "Expandable panel contract tests failed."
    exit 1
fi

echo "Running widgets page filter contract tests..."
if ! python3 "$SCRIPT_DIR/test_widgets_page_filters.py"; then
    echo "Widgets page filter contract tests failed."
    exit 1
fi

echo "Running plugin options section tests..."
if ! python3 "$SCRIPT_DIR/test_plugin_options_sections.py"; then
    echo "Plugin options section tests failed."
    exit 1
fi

echo "Running widget size row tests..."
if ! python3 "$SCRIPT_DIR/test_widget_size_row.py"; then
    echo "Widget size row tests failed."
    exit 1
fi

echo "Running widget grid lattice tests..."
if ! python3 "$SCRIPT_DIR/test_widget_grid_lattice.py"; then
    echo "Widget grid lattice tests failed."
    exit 1
fi

echo "Running widget transparency opacity tests..."
if ! python3 "$SCRIPT_DIR/test_widget_transparency_opacity.py"; then
    echo "Widget transparency opacity tests failed."
    exit 1
fi

echo "Running widget interaction mode tests..."
if ! python3 "$SCRIPT_DIR/test_widget_interaction_modes.py"; then
    echo "Widget interaction mode tests failed."
    exit 1
fi

# Brings its own headless weston, so it needs no display of its own - but it
# does need weston, and skips without it.
echo "Running widget interaction runtime tests..."
if ! python3 "$SCRIPT_DIR/test_widget_interaction_runtime.py"; then
    echo "Widget interaction runtime tests failed."
    exit 1
fi

echo "Running widget grip lock tests..."
if ! python3 "$SCRIPT_DIR/test_widget_grip_lock.py"; then
    echo "Widget grip lock tests failed."
    exit 1
fi

# Brings its own headless weston, like the interaction runtime tests above.
echo "Running widget resize grip runtime tests..."
if ! python3 "$SCRIPT_DIR/test_widget_resize_grip_runtime.py"; then
    echo "Widget resize grip runtime tests failed."
    exit 1
fi

echo "Running edit mode contract tests..."
if ! python3 "$SCRIPT_DIR/test_edit_mode_contract.py"; then
    echo "Edit mode contract tests failed."
    exit 1
fi

# Edit Mode may change placement, order, span and presence - nothing else.
# Settings is one click away FROM the mode, so a settings row duplicated into
# the editor is a second call site for a config write (spec 9); the allowlist
# in this lint is the spec and the lint is the receipt.
echo "Running edit mode scope lint..."
if ! python3 "$SCRIPT_DIR/lint_edit_mode_scope.py"; then
    echo "Edit mode scope lint failed."
    exit 1
fi

# Stage 9 of Edit Mode: the lock screen's preview must not be able to
# authenticate. The one contract in the mode whose failure is a security bug
# rather than a layout bug - every sweep in it asserts it still FOUND the
# thing it swept, because a grep that matches nothing must fail, not pass.
echo "Running lock preview contract tests..."
if ! python3 "$SCRIPT_DIR/test_lock_preview_contract.py"; then
    echo "Lock preview contract tests failed."
    exit 1
fi

# Stage 9b: the lock islands' order - the schema's defaults pinned to the
# resolver's, the islands rendered through the one resolver, and the reorder
# committing through the shared arithmetic at literal paths.
echo "Running lock islands contract tests..."
if ! python3 "$SCRIPT_DIR/test_lock_islands_contract.py"; then
    echo "Lock islands contract tests failed."
    exit 1
fi

# Whether a drag still lands where the pointer put it once the desktop is drawn
# at a scale. Nothing static can see that: the drag is hand-computed and the
# transform is only SUPPOSED to cancel itself out. Brings its own weston.
echo "Running edit mode runtime tests..."
if ! python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"; then
    echo "Edit mode runtime tests failed."
    exit 1
fi

# What the mode LOOKS like: the card's corner, the lattice sitting under the
# widgets, and the chrome being gone once the mode is left. Every one of those
# reads as correct in the source and is only answerable in pixels. Brings its
# own weston.
echo "Running edit mode chrome tests..."
if ! python3 "$SCRIPT_DIR/test_edit_mode_chrome.py"; then
    echo "Edit mode chrome tests failed."
    exit 1
fi

# The drawer's column distributes its height, and a chrome row that fills eats
# the list: stage 5 shipped with the tab row at 831px of 936 and the list at 24,
# which no source check can see.
echo "Running edit mode drawer layout tests..."
if ! python3 "$SCRIPT_DIR/test_edit_mode_drawer_layout.py"; then
    echo "Edit mode drawer layout tests failed."
    exit 1
fi

echo "Running dock position contract tests..."
if ! python3 "$SCRIPT_DIR/test_dock_position_contract.py"; then
    echo "Dock position contract tests failed."
    exit 1
fi

echo "Running settings search shortcut tests..."
if ! python3 "$SCRIPT_DIR/test_settings_search_shortcuts.py"; then
    echo "Settings search shortcut tests failed."
    exit 1
fi

echo "Running launcher result input observation check..."
if ! python3 "$SCRIPT_DIR/test_launcher_result_inputs.py"; then
    echo "Launcher result input observation check failed."
    exit 1
fi

echo "Running settings page id tests..."
if ! python3 "$SCRIPT_DIR/test_settings_page_ids.py"; then
    echo "Settings page id tests failed."
    exit 1
fi

# Stage 8 of Edit Mode: the bar and the dock edited in place. What it pins is
# silent on screen - a suspension that touches `visible` destroys a layer
# surface, and an affordance wired into one bar orientation and not the other
# is invisible on a default screen.
echo "Running bar/dock edit-mode contract tests..."
if ! python3 "$SCRIPT_DIR/test_bar_dock_edit_contract.py"; then
    echo "Bar/dock edit-mode contract tests failed."
    exit 1
fi

# The bar's in-place edit gesture: a drag along the bar reorders, a drag
# across it does not, at both orientations - the axis-inert comparison only
# real mouse events can see. Brings its own headless weston.
echo "Running bar edit runtime tests..."
if ! python3 "$SCRIPT_DIR/test_bar_edit_runtime.py"; then
    echo "Bar edit runtime tests failed."
    exit 1
fi

# The bar's reposition: one registry per bar wired into every bucket delegate
# of both trees, animating a transform rather than a coordinate the layout
# writes. Source-only, because the runtime half below skips wherever weston is
# missing - which is CI, which is where a divergence between the two bars would
# go unseen.
echo "Running bar reposition contract tests..."
if ! python3 "$SCRIPT_DIR/test_bar_flip_contract.py"; then
    echo "Bar reposition contract tests failed."
    exit 1
fi

# ...and the half that can tell the reposition from the teleport it replaces:
# it samples where each slot is DRAWN mid-reflow, at three bucket anchorings
# and both orientations. Brings its own headless weston and its own session bus.
echo "Running bar reposition runtime tests..."
if ! python3 "$SCRIPT_DIR/test_bar_flip_runtime.py"; then
    echo "Bar reposition runtime tests failed."
    exit 1
fi

# Stage 9b: the lock islands' reorder, driven with real mouse events on the
# real LockSurface with the preview context - the overlay's eater, the shared
# gesture, move semantics, the storedOrder merge, and both cancel paths.
# Brings its own headless weston.
# A screen-sized Overlay surface with nothing in it still sits over every
# fullscreen window, and an infinite animation keeps the compositor repainting
# the whole output: together they cost a fullscreen game half its frames.
echo "Running surface stand-down contract..."
if ! python3 "$SCRIPT_DIR/test_surface_standdown_contract.py"; then
    echo "Surface stand-down contract failed."
    exit 1
fi

echo "Running infinite animation visibility lint..."
if ! python3 "$SCRIPT_DIR/lint_infinite_animation_visibility.py"; then
    echo "Infinite animation visibility lint failed."
    exit 1
fi

# The Lockscreen tab is a filter on the desktop viewport, and the palette is one
# of the things it filters: stage 9 switched every layer's source and left the
# theme keyed on the session lock, so the tab drew the lock's wallpaper under
# the desktop's colours.
# Two widget layouts in one store: the lock's inherits the desktop's until the
# first Lockscreen-tab move forks it. The arithmetic is tst_layout_surfaces
# (qmltestrunner, below); this pins the writers, the store shape and presets.
echo "Running layout surfaces contract..."
if ! python3 "$SCRIPT_DIR/test_layout_surfaces_contract.py"; then
    echo "Layout surfaces contract failed."
    exit 1
fi

echo "Running lock look palette tests..."
if ! python3 "$SCRIPT_DIR/test_lock_look_palette.py"; then
    echo "Lock look palette tests failed."
    exit 1
fi

echo "Running lock island reorder runtime tests..."
if ! python3 "$SCRIPT_DIR/test_lock_island_reorder_runtime.py"; then
    echo "Lock island reorder runtime tests failed."
    exit 1
fi

# A column of dock icons can lay out perfectly and still refuse to reorder,
# because every slot centre shares an x - only real mouse events see that.
# Brings its own headless weston.
echo "Running dock edge runtime tests..."
if ! python3 "$SCRIPT_DIR/test_dock_edge_runtime.py"; then
    echo "Dock edge runtime tests failed."
    exit 1
fi

# Counts the qalc processes a typed query really starts, with a counting stub
# named `qalc` first on PATH. A unit test can check the gate's predicate; only
# a real shell can see how often the call site fires. Brings its own weston.
echo "Running launcher qalc spawn runtime tests..."
if ! python3 "$SCRIPT_DIR/test_launcher_qalc_runtime.py"; then
    echo "Launcher qalc spawn runtime tests failed."
    exit 1
fi

# Writes and reads a real launch-history store, and ranks the machine's own
# desktop entries through it: whether AppSearch consults AppUsage at all is
# invisible to a pure-logic test. Brings its own headless weston.
echo "Running app usage store runtime tests..."
if ! python3 "$SCRIPT_DIR/test_app_usage_runtime.py"; then
    echo "App usage store runtime tests failed."
    exit 1
fi

# Renders real cards and reads the pixels under them: the shadow is not
# reachable from a source-text check. Brings its own headless weston.
echo "Running widget card shadow tests..."
if ! python3 "$SCRIPT_DIR/test_card_shadow.py"; then
    echo "Widget card shadow tests failed."
    exit 1
fi

# The card above is rendered on its own. This renders the widget that composes
# one: calendar is content-sized, so a card that failed to resolve leaves a
# zero-size widget rather than an error, and a `dragging` that never arrives
# leaves a shadow that never lifts. Brings its own headless weston.
# Enumerated, not globbed - which is why these three could exist, pass by hand
# and be enforced by nothing. Added when a review counted the files run_tests.sh
# names against the files on disk.
echo "Running harness compositor-reach lint..."
if ! python3 "$SCRIPT_DIR/lint_harness_compositor_reach.py"; then
    echo "Harness compositor-reach lint failed."
    exit 1
fi

# A harness that stopped checking still reports `failures: 0`, and its driver
# still passes. Every verdict therefore states how many checks ran, and every
# driver asserts that number as a literal it holds itself.
echo "Running harness check-count lint..."
if ! python3 "$SCRIPT_DIR/lint_harness_check_counts.py"; then
    echo "Harness check-count lint failed."
    exit 1
fi

echo "Running settings search index tests..."
if ! python3 "$SCRIPT_DIR/test_settings_search_index.py"; then
    echo "Settings search index tests failed."
    exit 1
fi

echo "Running bar hover region tests..."
if ! python3 "$SCRIPT_DIR/test_bar_hover_region.py"; then
    echo "Bar hover region tests failed."
    exit 1
fi

# The two bars draw the same layout out of the same directory, and each used to
# resolve a widget to a file on its own. Only the horizontal one ever learned
# `plugin:`, so every plugin bar widget was an empty stub on a vertical bar.
echo "Running bar widget parity tests..."
if ! python3 "$SCRIPT_DIR/test_bar_widget_parity.py"; then
    echo "Bar widget parity tests failed."
    exit 1
fi

# The bar widget catalogue has one home (BarWidgets.qml) and the settings page
# reads it; a second copy in BarConfig is the drift the promotion removed.
echo "Running bar widget catalogue tests..."
if ! python3 "$SCRIPT_DIR/test_bar_widgets_catalogue.py"; then
    echo "Bar widget catalogue tests failed."
    exit 1
fi

echo "Running cheatsheet width budget tests..."
if ! python3 "$SCRIPT_DIR/test_cheatsheet_width_budget.py"; then
    echo "Cheatsheet width budget tests failed."
    exit 1
fi

echo "Running calendar card tests..."
if ! python3 "$SCRIPT_DIR/test_calendar_card.py"; then
    echo "Calendar card tests failed."
    exit 1
fi

# The same measurement for the five widgets that are not cards, each scored
# against a twin of itself with the elevation suppressed. Also weston-bound.
echo "Running widget elevation tests..."
if ! python3 "$SCRIPT_DIR/test_widget_elevation.py"; then
    echo "Widget elevation tests failed."
    exit 1
fi

# The grip harness above reads settled sizes on purpose, so it passes whether a
# span change is animated or instant. This one samples the size mid-change,
# which is the only way to tell a Behavior that ticks from one that never does.
echo "Running widget resize motion runtime tests..."
if ! python3 "$SCRIPT_DIR/test_widget_resize_motion_runtime.py"; then
    echo "Widget resize motion runtime tests failed."
    exit 1
fi

# The source half is static. The runtime half pans a real WidgetCanvas under
# real PluginWidgets and brings its own headless weston, so it needs no display
# of its own - but it does need weston, and skips without it.
echo "Running widget parallax opt-out tests..."
if ! python3 "$SCRIPT_DIR/test_widget_parallax_optout.py"; then
    echo "Widget parallax opt-out tests failed."
    exit 1
fi

echo "Running widget group selection tests..."
if ! python3 "$SCRIPT_DIR/test_widget_group_selection.py"; then
    echo "Widget group selection tests failed."
    exit 1
fi

# Brings its own headless weston, like the interaction runtime tests above.
echo "Running widget group drag runtime tests..."
if ! python3 "$SCRIPT_DIR/test_widget_group_drag_runtime.py"; then
    echo "Widget group drag runtime tests failed."
    exit 1
fi

# Brings its own headless weston, like the interaction runtime tests above.
echo "Running widget edge snap runtime tests..."
if ! python3 "$SCRIPT_DIR/test_widget_edge_snap_runtime.py"; then
    echo "Widget edge snap runtime tests failed."
    exit 1
fi

echo "Running widget plugin migration tests..."
if ! python3 "$SCRIPT_DIR/test_widget_plugin_migration.py"; then
    echo "Widget plugin migration tests failed."
    exit 1
fi

echo "Running notes store contract tests..."
if ! python3 "$SCRIPT_DIR/test_notes_store_contract.py"; then
    echo "Notes store contract tests failed."
    exit 1
fi

# Launches a real Quickshell against throwaway XDG dirs, so it skips where
# there is no Wayland display - notably CI.
echo "Running notes migration runtime tests..."
if ! python3 "$SCRIPT_DIR/test_notes_migration_runtime.py"; then
    echo "Notes migration runtime tests failed."
    exit 1
fi

# Brings its own headless weston, so it needs no display of its own - but it
# does need weston, and skips without it.
echo "Running notes surfaces runtime tests..."
if ! python3 "$SCRIPT_DIR/test_notes_surfaces_runtime.py"; then
    echo "Notes surfaces runtime tests failed."
    exit 1
fi

# Also brings its own weston, plus its own D-Bus session so the harness's
# notification server is the one notify-send reaches rather than the caller's.
echo "Running notification card list runtime tests..."
if ! python3 "$SCRIPT_DIR/test_notification_cards_runtime.py"; then
    echo "Notification card list runtime tests failed."
    exit 1
fi

echo "Running plugin installer tests..."
if ! python3 "$SCRIPT_DIR/test_plugin_installer.py"; then
    echo "Plugin installer tests failed."
    exit 1
fi

echo "Running plugin uninstaller tests..."
if ! python3 "$SCRIPT_DIR/test_plugin_uninstaller.py"; then
    echo "Plugin uninstaller tests failed."
    exit 1
fi

echo "Running terminal background tests..."
if ! python3 "$SCRIPT_DIR/test_terminal_background.py"; then
    echo "Terminal background tests failed."
    exit 1
fi

echo "Running Matugen application theme tests..."
if ! python3 "$SCRIPT_DIR/test_matugen_app_themes.py"; then
    echo "Matugen application theme tests failed."
    exit 1
fi

echo "Running tmux dots tests..."
if ! python3 "$SCRIPT_DIR/test_tmux_dots.py"; then
    echo "tmux dots tests failed."
    exit 1
fi

echo "Running SDDM pin reachability test..."
if ! python3 "$SCRIPT_DIR/test_sddm_pin_reachable.py"; then
    echo "SDDM pin reachability test failed."
    exit 1
fi

echo "Running parallax migration runtime tests..."
if ! python3 "$SCRIPT_DIR/test_parallax_migration_runtime.py"; then
    echo "Parallax migration runtime tests failed."
    exit 1
fi

# One motion policy: that every tier still routes through it, and that the
# reduce-motion floor stays a named state rather than the far end of a slider.
echo "Running motion policy contract tests..."
if ! python3 "$SCRIPT_DIR/test_motion_policy_contract.py"; then
    echo "Motion policy contract tests failed."
    exit 1
fi

# ...and the same thing read back off a real shell against a seeded config,
# because the QML default and the adapter's merged answer are different
# numbers and only the second one runs.
echo "Running motion multiplier runtime tests..."
if ! python3 "$SCRIPT_DIR/test_motion_multiplier_runtime.py"; then
    echo "Motion multiplier runtime tests failed."
    exit 1
fi

echo "Running OSD indicator swap tests..."
if ! python3 "$SCRIPT_DIR/test_osd_indicator_swap.py"; then
    echo "OSD indicator swap tests failed."
    exit 1
fi

echo "Running Prism Launcher instance tests..."
if ! python3 "$SCRIPT_DIR/test_prism_instances.py"; then
    echo "Prism Launcher instance tests failed."
    exit 1
fi

echo "Running wallpaper thumbnail fallback tests..."
if ! python3 "$SCRIPT_DIR/test_thumbnail_fallback.py"; then
    echo "Wallpaper thumbnail fallback tests failed."
    exit 1
fi

echo "Running background fullscreen suppression tests..."
if ! python3 "$SCRIPT_DIR/test_background_fullscreen_suppression.py"; then
    echo "Background fullscreen suppression tests failed."
    exit 1
fi

echo "Running wallpaper transition catalogue tests..."
if ! python3 "$SCRIPT_DIR/test_wallpaper_transitions.py"; then
    echo "Wallpaper transition catalogue tests failed."
    exit 1
fi

echo "Running Wallpaper Engine integration tests..."
if ! python3 "$SCRIPT_DIR/test_wallpaper_engine.py"; then
    echo "Wallpaper Engine integration tests failed."
    exit 1
fi

echo "Running preset state tests..."
if ! python3 "$SCRIPT_DIR/test_presets.py"; then
    echo "Preset state tests failed."
    exit 1
fi

echo "Running Settings navigation tests..."
if ! python3 "$SCRIPT_DIR/test_settings_navigation.py"; then
    echo "Settings navigation tests failed."
    exit 1
fi

echo "Running expressive design system tests..."
if ! python3 "$SCRIPT_DIR/test_expressive_design_system.py"; then
    echo "Expressive design system tests failed."
    exit 1
fi

echo "Running icon theme scanner tests..."
if ! python3 "$SCRIPT_DIR/test_scan_icon_themes.py"; then
    echo "Icon theme scanner tests failed."
    exit 1
fi

echo "Running icon theme apply tests..."
if ! python3 "$SCRIPT_DIR/test_icon_theme_apply.py"; then
    echo "Icon theme apply tests failed."
    exit 1
fi

echo "Running cursor theme scanner tests..."
if ! python3 "$SCRIPT_DIR/test_scan_cursor_themes.py"; then
    echo "Cursor theme scanner tests failed."
    exit 1
fi

echo "Running cursor theme apply tests..."
if ! python3 "$SCRIPT_DIR/test_cursor_theme_apply.py"; then
    echo "Cursor theme apply tests failed."
    exit 1
fi

echo "Running sound theme scanner tests..."
if ! python3 "$SCRIPT_DIR/test_sound_theme_scan.py"; then
    echo "Sound theme scanner tests failed."
    exit 1
fi

echo "Running default config tests..."
if ! python3 "$SCRIPT_DIR/test_default_config.py"; then
    echo "Default config tests failed."
    exit 1
fi

echo "Running bar geometry contract tests..."
if ! python3 "$SCRIPT_DIR/test_bar_geometry_contract.py"; then
    echo "Bar geometry contract tests failed."
    exit 1
fi

# The bar's exclusive zone lives on an invisible reserver window so the
# compositor's reflow can ride the same curve as the bar's slide. Nothing about
# a layer surface's exclusive zone is observable from qmltestrunner or from
# headless weston, so this is the source contract; the measurement lives in
# tests/run_bar_exclusive_zone_probe.sh, which needs a nested Hyprland.
echo "Running bar exclusive zone reserver contract tests..."
if ! python3 "$SCRIPT_DIR/test_bar_exclusive_zone_reserver.py"; then
    echo "Bar exclusive zone reserver contract tests failed."
    exit 1
fi

echo "Running dock motion contract tests..."
if ! python3 "$SCRIPT_DIR/test_dock_motion.py"; then
    echo "Dock motion contract tests failed."
    exit 1
fi

echo "Running config directory migration tests..."
if ! python3 "$SCRIPT_DIR/test_config_migration.py"; then
    echo "Config directory migration tests failed."
    exit 1
fi

# Launches a real Quickshell and forces the startup race the migration used to
# lose. Brings its own headless weston, so it needs no display of its own - but
# it does need weston, and skips without it.
echo "Running config directory migration runtime tests..."
if ! python3 "$SCRIPT_DIR/test_config_dir_migration_runtime.py"; then
    echo "Config directory migration runtime tests failed."
    exit 1
fi

# Both halves of the stale grp:win_space_toggle clear (issue #69) live in
# on-disk state - a marker burned against a config that never carried the
# value, and the generated lua the compositor actually reads - so this needs a
# real Quickshell against real files rather than a unit test.
echo "Running stale kbOptions clear runtime tests..."
if ! python3 "$SCRIPT_DIR/test_kboptions_migration_runtime.py"; then
    echo "Stale kbOptions clear runtime tests failed."
    exit 1
fi

# The block is a set of paths into the theme's directory and at the apply
# script sudo will accept; the directory was renamed and the script moved. A
# wrong path here means the login screen silently stops following the
# wallpaper, and restoring only part of the block is how it stopped last time.
echo "Running SDDM matugen hook restore tests..."
if ! python3 "$SCRIPT_DIR/test_sddm_matugen_hook_restore.py"; then
    echo "SDDM matugen hook restore tests failed."
    exit 1
fi

# Uninstall step 5 hands the machine to the theme's uninstaller, which removes
# the drop-in carrying Current= along with the theme. Firing it on a theme we
# did not install is somebody else's login screen.
echo "Running SDDM uninstall ownership tests..."
if ! python3 "$SCRIPT_DIR/test_sddm_uninstall_ownership.py"; then
    echo "SDDM uninstall ownership tests failed."
    exit 1
fi

echo "Running SDDM theme source tests..."
if ! python3 "$SCRIPT_DIR/test_sddm_theme_source.py"; then
    echo "SDDM theme source tests failed."
    exit 1
fi

# The CI-visible half of the quick toggle grid's delegate rules: the runtime
# harness below needs a Wayland session and skips where these would be undone.
echo "Running quick toggle model contract tests..."
if ! python3 "$SCRIPT_DIR/test_quick_toggle_model_contract.py"; then
    echo "Quick toggle model contract tests failed."
    exit 1
fi

# Renders the real quick toggle panel and performs the layout edits edit mode
# performs. The failure is invisible in the config and a restart hides it, so
# it needs a real shell rather than a unit test. See the module docstring.
echo "Running quick toggle layout runtime tests..."
if ! python3 "$SCRIPT_DIR/test_quick_toggles_layout_runtime.py"; then
    echo "Quick toggle layout runtime tests failed."
    exit 1
fi

echo "Running keyring migration tests..."
if ! python3 "$SCRIPT_DIR/test_keyring_migration.py"; then
    echo "Keyring migration tests failed."
    exit 1
fi

echo "Running Wallpaper Engine prebuilt installer tests..."
if ! python3 "$SCRIPT_DIR/test_wallpaperengine_prebuilt.py"; then
    echo "Wallpaper Engine prebuilt installer tests failed."
    exit 1
fi

echo "Running keybind cheatsheet parser tests..."
if ! python3 "$SCRIPT_DIR/test_get_keybinds.py"; then
    echo "keybind cheatsheet parser tests failed."
    exit 1
fi

echo "Running keybind override generator tests..."
if ! python3 "$SCRIPT_DIR/test_keybind_overrides.py"; then
    echo "keybind override generator tests failed."
    exit 1
fi

# Brings its own headless weston, so it needs no display of its own - but it
# does need weston, and skips without it.
echo "Running keybind override runtime tests..."
if ! python3 "$SCRIPT_DIR/test_keybind_overrides_runtime.py"; then
    echo "keybind override runtime tests failed."
    exit 1
fi

echo "Running momentum scroll contract tests..."
if ! python3 "$SCRIPT_DIR/test_momentum_scroll_contract.py"; then
    echo "momentum scroll contract tests failed."
    exit 1
fi

echo "Running lock palette parity tests..."
if ! python3 "$SCRIPT_DIR/test_lock_palette_parity.py"; then
    echo "lock palette parity tests failed."
    exit 1
fi

echo "Running scheme detection tests..."
if ! python3 "$SCRIPT_DIR/test_scheme_for_image.py"; then
    echo "scheme detection tests failed."
    exit 1
fi

echo "Running color generator tests..."
if ! python3 "$SCRIPT_DIR/test_generate_colors_material.py"; then
    echo "color generator tests failed."
    exit 1
fi

echo "Running installer file sync tests..."
if ! python3 "$SCRIPT_DIR/test_installer_file_sync.py"; then
    echo "installer file sync tests failed."
    exit 1
fi

# get.sh resets the update checkout onto $REF, and that checkout is a repo the
# user can commit in. Drives throwaway origin/DEST repos inside a tempdir, so
# it can never reach the machine's real one.
echo "Running get.sh local-work preservation tests..."
if ! python3 "$SCRIPT_DIR/test_get_sh_preserves_local_work.py"; then
    echo "get.sh local-work preservation tests failed."
    exit 1
fi

echo "Running installer legacy migration tests..."
if ! python3 "$SCRIPT_DIR/test_installer_legacy_migration.py"; then
    echo "installer legacy migration tests failed."
    exit 1
fi

echo "Running installer cancel/trap contract tests..."
if ! python3 "$SCRIPT_DIR/test_installer_greeting_traps.py"; then
    echo "installer cancel/trap contract tests failed."
    exit 1
fi

echo "Running uninstaller login-shell rescue tests..."
if ! python3 "$SCRIPT_DIR/test_uninstall_login_shell.py"; then
    echo "uninstaller login-shell rescue tests failed."
    exit 1
fi

echo "Running updates service contract tests..."
if ! python3 "$SCRIPT_DIR/test_updates_contract.py"; then
    echo "updates service contract tests failed."
    exit 1
fi

echo "Running conflict killer safety tests..."
if ! python3 "$SCRIPT_DIR/test_conflict_killer_contract.py"; then
    echo "conflict killer safety tests failed."
    exit 1
fi

echo "Running polkit service contract tests..."
if ! python3 "$SCRIPT_DIR/test_polkit_service_contract.py"; then
    echo "polkit service contract tests failed."
    exit 1
fi

echo "Running ydotool safety contract tests..."
if ! python3 "$SCRIPT_DIR/test_ydotool_contract.py"; then
    echo "ydotool safety contract tests failed."
    exit 1
fi

# Brings its own headless weston and fake hyprsunset/hyprctl/pidof binaries, so
# it needs no display of its own and never touches the caller's screen - but it
# does need weston, and skips without it.
echo "Running night light state runtime tests..."
if ! python3 "$SCRIPT_DIR/test_nightlight_state_runtime.py"; then
    echo "Night light state runtime tests failed."
    exit 1
fi

echo "Running brightness/system info contract tests..."
if ! python3 "$SCRIPT_DIR/test_brightness_systeminfo_contract.py"; then
    echo "brightness/system info contract tests failed."
    exit 1
fi

echo "Running Clight integration contract tests..."
if ! python3 "$SCRIPT_DIR/test_clight_contract.py"; then
    echo "Clight integration contract tests failed."
    exit 1
fi

# Brings its own headless weston and fake busctl/brightnessctl/clight (plus
# the night-light trio) binaries, so it needs no display of its own - but it
# does need weston, and skips without it.
echo "Running Clight integration runtime tests..."
if ! python3 "$SCRIPT_DIR/test_clight_integration_runtime.py"; then
    echo "Clight integration runtime tests failed."
    exit 1
fi

echo "Running shared widget contract tests..."
if ! python3 "$SCRIPT_DIR/test_shared_widget_contracts.py"; then
    echo "Shared widget contract tests failed."
    exit 1
fi

# The source half is static. The runtime half opens a real settings page
# against a real config and brings its own headless weston, so it needs no
# display of its own - but it does need weston, and skips without it.
echo "Running config control write-back tests..."
if ! python3 "$SCRIPT_DIR/test_config_control_write_back.py"; then
    echo "Config control write-back tests failed."
    exit 1
fi

echo "Running Docker memory-safety contract tests..."
if ! python3 "$SCRIPT_DIR/test_docker_memory_safety.py"; then
    echo "Docker memory-safety contract tests failed."
    exit 1
fi

echo "Running Discord voice plugin tests..."
if ! python3 "$SCRIPT_DIR/test_discord_voice_plugin.py"; then
    echo "Discord voice plugin tests failed."
    exit 1
fi

echo "Running MPRIS controller contract tests..."
if ! python3 "$SCRIPT_DIR/test_mpris_controller_contract.py"; then
    echo "MPRIS controller contract tests failed."
    exit 1
fi

echo "Running cava spectrum contract tests..."
if ! python3 "$SCRIPT_DIR/test_cava_contract.py"; then
    echo "Cava spectrum contract tests failed."
    exit 1
fi

echo "Running lyrics widget contract tests..."
if ! python3 "$SCRIPT_DIR/test_lyrics_widget_contract.py"; then
    echo "Lyrics widget contract tests failed."
    exit 1
fi

# Re-runs tst_weather_forecast.qml under a far-east and a far-west timezone.
# On a UTC runner - which is CI - a local date and a UTC one are the same
# string, so the unit test cannot tell them apart on its own.
echo "Running weather forecast contract tests..."
if ! python3 "$SCRIPT_DIR/test_weather_forecast_contract.py"; then
    echo "Weather forecast contract tests failed."
    exit 1
fi

# Brings its own headless weston and its own bus. The card unrolls from the
# content's first DRAWN section, so a section added to a popup silently changes
# what that popup opens at - and a settled bar is the same height whether it
# grew or teleported, so the bars are sampled in flight.
echo "Running weather popup hero runtime tests..."
if ! python3 "$SCRIPT_DIR/test_weather_popup_hero_runtime.py"; then
    echo "Weather popup hero runtime tests failed."
    exit 1
fi

echo "Running currency service safety tests..."
if ! python3 "$SCRIPT_DIR/test_currency_service_contract.py"; then
    echo "Currency service safety tests failed."
    exit 1
fi

echo "Running ripple lifecycle safety tests..."
if ! python3 "$SCRIPT_DIR/test_ripple_lifecycle_contract.py"; then
    echo "Ripple lifecycle safety tests failed."
    exit 1
fi

echo "Running EFI boot contract tests..."
if ! python3 "$SCRIPT_DIR/test_efiboot_contract.py"; then
    echo "EFI boot contract tests failed."
    exit 1
fi

echo "Running plymouth theme tests..."
if ! python3 "$SCRIPT_DIR/test_plymouth_theme.py"; then
    echo "Plymouth theme tests failed."
    exit 1
fi

echo "Running screen recorder tests..."
if ! python3 "$SCRIPT_DIR/test_screen_record.py"; then
    echo "Screen recorder tests failed."
    exit 1
fi

echo "Running SDR tonemap tests..."
if ! python3 "$SCRIPT_DIR/test_tonemap_sdr.py"; then
    echo "SDR tonemap tests failed."
    exit 1
fi

echo "Running Wallpaper Engine still tests..."
if ! python3 "$SCRIPT_DIR/test_we_still.py"; then
    echo "Wallpaper Engine still tests failed."
    exit 1
fi

echo "Running clock depth cache tests..."
if ! python3 "$SCRIPT_DIR/test_clock_depth_cache.py"; then
    echo "Clock depth cache tests failed."
    exit 1
fi

echo "Running subject mask refinement tests..."
if ! python3 "$SCRIPT_DIR/test_subject_mask_refine.py"; then
    echo "Subject mask refinement tests failed."
    exit 1
fi

echo "Running clock depth model list tests..."
if ! python3 "$SCRIPT_DIR/test_clock_depth_models.py"; then
    echo "Clock depth model list tests failed."
    exit 1
fi

echo "Running clock depth geometry lint..."
if ! python3 "$SCRIPT_DIR/lint_clock_depth_geometry.py"; then
    echo "Clock depth geometry lint failed."
    exit 1
fi

echo "Running clock depth desktop selector contract tests..."
if ! python3 "$SCRIPT_DIR/test_clock_depth_select_contract.py"; then
    echo "Clock depth desktop selector contract tests failed."
    exit 1
fi

echo "Running clock depth compositing tests..."
if ! python3 "$SCRIPT_DIR/test_clock_depth_compositing.py"; then
    echo "Clock depth compositing tests failed."
    exit 1
fi

echo "Running clock depth no-op tests..."
if ! python3 "$SCRIPT_DIR/test_clock_depth_noop.py"; then
    echo "Clock depth no-op tests failed."
    exit 1
fi

echo "Running greeter sync tests..."
if ! python3 "$SCRIPT_DIR/test_greeter_sync.py"; then
    echo "Greeter sync tests failed."
    exit 1
fi

echo "Running drop shelf summon tests..."
if ! python3 "$SCRIPT_DIR/test_dropshelf_summon.py"; then
    echo "Drop shelf summon tests failed."
    exit 1
fi

echo "Running screensaver on-demand tests..."
if ! python3 "$SCRIPT_DIR/test_screensaver_on_demand.py"; then
    echo "Screensaver on-demand tests failed."
    exit 1
fi

echo "Running event-loop safety tests..."
if ! python3 "$SCRIPT_DIR/test_event_loop_safety_contract.py"; then
    echo "Event-loop safety tests failed."
    exit 1
fi

echo "Running screenshot result contract tests..."
if ! python3 "$SCRIPT_DIR/test_screenshot_result_contract.py"; then
    echo "screenshot result contract tests failed."
    exit 1
fi

echo "Running experimental updater contract tests..."
if ! python3 "$SCRIPT_DIR/test_exp_update_contract.py"; then
    echo "experimental updater contract tests failed."
    exit 1
fi

echo "Running OpenRGB service contract tests..."
if ! python3 "$SCRIPT_DIR/test_openrgb_contract.py"; then
    echo "OpenRGB service contract tests failed."
    exit 1
fi

echo "Running OpenRGB detector sync tests..."
if ! python3 "$SCRIPT_DIR/test_openrgb_detector_sync.py"; then
    echo "OpenRGB detector sync tests failed."
    exit 1
fi

# The QML suite drives a logic-only double; this is the sync check that makes
# its green transfer to the real service, plus the busctl argv/id-guard pins.
echo "Running Phone Connect contract tests..."
if ! python3 "$SCRIPT_DIR/test_phone_connect_contract.py"; then
    echo "Phone Connect contract tests failed."
    exit 1
fi

# The stream's process lifetime, which no source check and no unit test can
# reach: a real shell, a fake busctl whose monitor verb streams one signal in
# one case and exits instantly in the other, and the spawn TIMESTAMPS read
# back - because "it stopped after six spawns" is also true of six spawns in
# six milliseconds, which is the starvation bug itself.
echo "Running Phone Connect monitor runtime tests..."
if ! python3 "$SCRIPT_DIR/test_phone_connect_monitor_runtime.py"; then
    echo "Phone Connect monitor runtime tests failed."
    exit 1
fi

echo "Running registry entry validator tests..."
if ! python3 "$SCRIPT_DIR/test_registry_validate.py"; then
    echo "Registry entry validator tests failed."
    exit 1
fi

echo "Running plugin store contract tests..."
if ! python3 "$SCRIPT_DIR/test_plugin_store_contract.py"; then
    echo "Plugin store contract tests failed."
    exit 1
fi

echo "Running media layout contract tests..."
if ! python3 "$SCRIPT_DIR/test_media_layouts_contract.py"; then
    echo "Media layout contract tests failed."
    exit 1
fi

# Contract: what turns an on-screen keyboard key's span into pixels. The
# layouts themselves are data and are checked by tst_osk_layouts.qml; this is
# the conversion, which the data cannot see - a second shape table, a key gap
# that is not the row's gap, or a key that fills the row and so decides where
# every key after it goes.
echo "Running on-screen keyboard key contract tests..."
if ! python3 "$SCRIPT_DIR/test_osk_key_contract.py"; then
    echo "On-screen keyboard key contract tests failed."
    exit 1
fi

if [[ "${RUN_DOCKER_RUNTIME_MEMORY_TEST:-0}" == "1" ]]; then
    echo "Running capped Docker runtime memory test..."
    bash "$SCRIPT_DIR/run_docker_memory_test.sh"
fi

# Design-system and bundled-package compile check. It needs a real Quickshell
# process and therefore a compositor, so it skips rather than fails where there
# is no Wayland display - notably CI. Wiring it in at all is the point: two
# package names in its sweep had been dead since the ii->imi rename and nobody
# noticed, because nothing ever ran it.
echo "Running design system compile check..."
if [ -z "${WAYLAND_DISPLAY:-}" ] || ! command -v qs >/dev/null 2>&1; then
    echo "  SKIPPED (no WAYLAND_DISPLAY, or qs not on PATH)"
else
    DSC_OUT="$(cd "$PROJECT_ROOT" && timeout 120 qs -p DesignSystemCompile.qml 2>&1 | grep "DesignSystemCompile" || true)"
    if ! printf '%s' "$DSC_OUT" | grep -q "failures=0"; then
        echo "Design system compile check failed:" >&2
        printf '%s\n' "$DSC_OUT" >&2
        exit 1
    fi
    printf '  %s\n' "$DSC_OUT"
fi

# Run the test runner
"$QMLTESTRUNNER" \
    -import "$PROJECT_ROOT/tests/mocks" \
    -import "$PROJECT_ROOT/tests/imports" \
    -input "$PROJECT_ROOT/tests"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "All tests passed successfully!"
else
    echo "Test suite failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
