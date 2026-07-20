# Quickshell Configuration Regression Test Suite

This directory contains the regression test suite for the `end4-pC` Quickshell configuration.

## Testing Philosophy & Approach

Quickshell/QML shell configurations are interpreted live by `quickshell` and run in a graphical environment (Wayland/Hyprland) with live service dependencies (PipeWire, NetworkManager, Battery, etc.). Testing this environment poses two main challenges:
1. Running graphical tests headlessly in CI or during development without spawning a real shell window.
2. Isolating pure business logic (color calculations, resource parsing, config defaults) from live hardware/compositor states.

### Solution: Headless Unit Testing with `qmltestrunner` and Mocks
We leverage Qt's **`qmltestrunner`** (bundled with Qt6 Declarative Test package) to execute standard QML `TestCase` components. To isolate code from live shell states, we use a double-import strategy:
1. **Mocking the `Quickshell` C++ Types**: We provide mock types for `Quickshell` core features (like `Singleton`, `Process`, `FileView`, `ColorQuantizer`) inside `tests/mocks/Quickshell/`.
2. **Shadowing imports (`tests/imports/qs/`)**: To avoid polluting the workspace source code, we use a directory mapping in `tests/imports` where QML files are symlinked to mirror `import qs.services` or `import qs.modules.common`. Singletons are mapped using local `qmldir` configurations. 
3. **Mocking Select Singletons**: Singletons that perform disk I/O or run system commands (like `Directories.qml`) are fully mocked in `tests/imports/qs/modules/common/Directories.qml` to prevent unit tests from writing to the user's home directory.

The root `qs` module is also declared in `tests/imports/qs/qmldir`; its lightweight `GlobalStates` mock allows common singletons such as `Appearance` to retain their real runtime imports in headless tests.

This allows us to run tests headlessly, fast, and safely on any system with Qt6 installed.

---

## How to Run the Test Suite

A runner script is provided at the root of the test directory to locate `qmltestrunner` and launch the suite with the proper mock import paths:

```bash
./tests/run_tests.sh
```

---

## How to Add a New Test

1. **Create a Test File**: Add a file named `tst_<feature_name>.qml` inside the `tests/` directory. It must start with `tst_` for the runner to auto-discover it.
2. **Write the TestCase**:
   ```qml
   import QtQuick
   import QtTest
   import qs.services // To import services under services/
   import qs.modules.common // To import common singletons like Config

   TestCase {
       name: "MyFeatureTest"

       function test_my_feature() {
           compare(1 + 1, 2)
       }
   }
   ```
3. **Declare Dependencies**:
   - If the component you are testing imports a service or module that is not yet declared in `tests/imports/qs/services/qmldir` or `tests/imports/qs/modules/common/qmldir`, add it to the corresponding `qmldir` file.
   - If the component uses a `Quickshell` type not yet mocked, add a mock file for it in `tests/mocks/Quickshell/` and declare it in `tests/mocks/Quickshell/qmldir`.

---

## Code Coverage

The initial phase covers components that represent pure logic and do not require a live Hyprland session:

* **Color Math (`tst_color_utils.qml`)**: Tests `transparentize`, `solveOverlayColor`, and `applyAlpha` under `ColorUtils.qml`.
* **Config Schema (`tst_config.qml`)**: Validates that all critical settings have correct defaults defined.
* **Audio Device Name Priority (`tst_audio.qml`)**: Validates the priority selection of friendly audio device names (`description` > `nickname` > `"Unknown"`) and application display names.
* **System Stats Parser (`tst_resource_usage.qml`)**: Tests parsing functions for `/proc/meminfo` contents, `df -k` disk usage output, and `nvidia-smi` GPU/VRAM statistics.
* **Live Desktop Entry Resolution (`tst_live_desktop_entry.qml`)**: Tests `LiveDesktopEntry.qml` against a mock `DesktopEntries` (`tests/mocks/Quickshell/DesktopEntries.qml`) that can simulate `applications` populating after the resolver already exists, guarding against the dock's pinned-launcher regression where a `heuristicLookup()`-based binding never refreshed once the desktop entry database finished loading.

## Static Lints

In addition to the QML unit tests, `run_tests.sh` runs static lint checks first:

* **QML import lint (`lint_qml_imports.sh`)**: Fails if any `.qml` under `modules/` references the `Appearance` singleton as a bareword without `import qs.modules.common`. That import is not transitive through `qs.modules.common.widgets`; omitting it throws `ReferenceError: Appearance is not defined` per binding evaluation, and when the missing token feeds a positioner's `spacing`/`margin` the resulting NaN geometry pegs the shell at 100% CPU. A bulk token migration introduced exactly this, so the lint prevents recurrence.
* **Lockscreen theme lint (`lint_lockscreen_theme.sh`)**: Keeps transient lock colors owned by `MaterialThemeLoader`, verifies that its virtual-environment wrapper preserves wallpaper paths containing spaces, guards the precomputed palette cache/delayed transition, caps the animated palette-role budget, requires the bounded fast color duration, and prevents locking from switching to synthetic Hyprland workspaces. This avoids theme races, animation contention, and persistent compositor/screencopy state corruption.
* **Region selector capture lint (`lint_region_selector_capture.sh`)**: Requires the selector preview and final crop to share the same freshly generated `grim` image, with image caching disabled and visibility gated on decoding. This prevents an independent screencopy from displaying a stale compositor frame.
* **Plugin process lifecycle lint (`lint_plugin_processes.py`)**: Rejects bundled streaming processes with persistent `running` bindings unless they document restart-safe backoff, prevents Docker's known-runaway desktop host from being re-enabled, and keeps package bar entries behind exactly one loader instead of the runaway nested sizing path. This prevents instant-exit respawn loops and multi-gigabyte allocation failures from starving the shell session.
* **Plugin installer tests (`test_plugin_installer.py`)**: Verify remote package paths cannot be absolute or escape the plugin directory using `..`.
* **Expressive design-system tests (`test_expressive_design_system.py`)**: Keep the shared Material 3 Expressive library out of the plugin catalog, verify the complete port inventory, and require independent creator-attributed manifests for all six nandoroid desktop widgets.
* **Currency service safety tests (`test_currency_service_contract.py`)**: Require one debounced API request per refresh, stale-response invalidation, a bounded timeout, and a non-reentrant completion path without `XMLHttpRequest.abort()`. This prevents DNS outages or startup setting bindings from multiplying pending network callbacks on Quickshell's UI thread.
* **Ripple lifecycle safety tests (`test_ripple_lifecycle_contract.py`)**: Require ripple handlers to call their owning component explicitly and stop active animations before delegate destruction. This prevents media-player replacement or configuration reloads from repeatedly invoking functions through invalid QML contexts and stalling the event loop.
* **Event-loop safety tests (`test_event_loop_safety_contract.py`)**: Guard expired notification timers, prevent Loader/item dimension feedback in the bar, and restrict `mirrored` writes to visualizers. These checks cover the binding loops and invalid-object callbacks observed immediately before shell stalls. The module has also accumulated two adjacent UI-contract checks: that the Settings window is floated by its fixed size hints rather than by a runtime `hyprctl eval` rule (which never survives the shell's startup reload), and that the spacing lint covers the grid-gap and axis-padding property names whose spelling let raw literals past it.

### What the Python checks are, and are not

All of the `test_*.py` and `lint_*.py` checks above are **static assertions over
source text**, not behavioural tests. They pin the shape of a fix so it cannot
be silently undone, but they cannot observe a running shell, so a passing suite
never proves the absence of a runtime warning. Always read the live log after a
change as well.

Because they only match text, they are also sensitive to reformatting: prefer
asserting a distinctive single-line fragment over a multi-line block with baked
in indentation.

Modules written in the pytest style (bare `test_*` functions) **must** end with:

```python
if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
```

`run_tests.sh` invokes them as `python3 <file>`. Without that block the module
merely defines its functions and exits zero, and the whole file silently passes
without executing a single assertion. Three modules shipped in that state.

## Runtime harnesses (repository root)

`CurrencyRuntimeTest.qml`, `DesignSystemCompile.qml`, `DockerRuntimeTest.qml`,
`DockerBarControlRuntimeTest.qml`, and `DockerBarHostRuntimeTest.qml` are
manually launched harnesses, driven by `run_docker_memory_test.sh` via
`quickshell -p <file>`.

They live at the repository root on purpose and should not be moved into
`tests/`: `quickshell -p` roots the `qs` module at the directory of the file it
is given, so from `tests/` their `import qs.modules.ii.bar` would no longer
resolve.
