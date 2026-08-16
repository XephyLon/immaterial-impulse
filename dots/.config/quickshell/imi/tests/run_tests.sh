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

echo "Running doc citation lint..."
if ! python3 "$SCRIPT_DIR/lint_doc_citations.py"; then
    echo "Doc citation lint failed."
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

# Whether a drag still lands where the pointer put it once the desktop is drawn
# at a scale. Nothing static can see that: the drag is hand-computed and the
# transform is only SUPPOSED to cancel itself out. Brings its own weston.
echo "Running edit mode runtime tests..."
if ! python3 "$SCRIPT_DIR/test_edit_mode_runtime.py"; then
    echo "Edit mode runtime tests failed."
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
