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
echo "Running spacing token lint..."
if ! python3 "$SCRIPT_DIR/lint_spacing.py"; then
    echo "Spacing lint failed."
    exit 1
fi

echo "Running plugin process lifecycle lint..."
if ! python3 "$SCRIPT_DIR/lint_plugin_processes.py"; then
    echo "Plugin process lifecycle lint failed."
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

echo "Running wallpaper thumbnail fallback tests..."
if ! python3 "$SCRIPT_DIR/test_thumbnail_fallback.py"; then
    echo "Wallpaper thumbnail fallback tests failed."
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

echo "Running shared widget contract tests..."
if ! python3 "$SCRIPT_DIR/test_shared_widget_contracts.py"; then
    echo "Shared widget contract tests failed."
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

echo "Running lyrics widget contract tests..."
if ! python3 "$SCRIPT_DIR/test_lyrics_widget_contract.py"; then
    echo "Lyrics widget contract tests failed."
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

echo "Running event-loop safety tests..."
if ! python3 "$SCRIPT_DIR/test_event_loop_safety_contract.py"; then
    echo "Event-loop safety tests failed."
    exit 1
fi

if [[ "${RUN_DOCKER_RUNTIME_MEMORY_TEST:-0}" == "1" ]]; then
    echo "Running capped Docker runtime memory test..."
    bash "$SCRIPT_DIR/run_docker_memory_test.sh"
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
