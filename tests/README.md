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
