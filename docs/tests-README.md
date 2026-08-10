# Quickshell Configuration Regression Test Suite

This directory contains the regression test suite for the `Immaterial Impulse` Quickshell configuration.

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

Nothing here renders, but `qmltestrunner` still constructs a `QGuiApplication`, which aborts with
SIGABRT (exit 134) when Qt cannot resolve a platform plugin - over SSH, in a container, or in any
session without a display. `run_tests.sh` therefore defaults `QT_QPA_PLATFORM` to `offscreen`; set
it explicitly to override.

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
* **Music Title Cleanup (`tst_string_utils.qml`)**: Tests `StringUtils.cleanMusicTitle` - strips leading bracketed tags but keeps a fully-bracketed title (e.g. `[BLEED BLOOD]`) instead of blanking the media widget.
* **Battery Transient Swap (`tst_battery.qml`)**: In addition to threshold/health mapping, verifies the battery stays available and freezes its last-good percentage through a transient UPower `displayDevice` swap, so the widget doesn't flap and no false low-battery action fires.
* **Cava band shaping (`tst_cava_bands.qml`)**: Drives `modules/common/functions/cavaBands.js`, the arithmetic that fits the producer's spectrum onto whatever number of bars a consumer draws. Pins that downsampling averages rather than picking one index per bar — the `Math.floor(i * n / barCount)` idiom it replaces reached only 20 of the producer's 50 bands, so a peak landing between two picked indices never appeared — that upsampling interpolates and keeps both ends, that an absent spectrum yields zeros at the requested length rather than a short array, and that levels stay clamped to 0..1 through cava's autosens overshoot. Confirmed to redden under the index-picking implementation it replaces.
* **Per-lobe cookie radii (`tst_rounded_polygon_lobes.qml`)**: Drives `RoundedPolygon.starPerLobe()` — a scalar inner radius is byte-for-byte the old `star()`; an array of twelve radii produces twelve distinct lobes that survive the rounding and reach the built cubics; *which* lobe moved changes the outline (magnitude alone would pass if every lobe read `radii[0]`); and a QML `list<real>` is not mistaken for a scalar. The shapes themselves are not testable here — `qmltestrunner` cannot construct Quickshell types and nothing draws a `Canvas`.
* **Visualizer band folding (`tst_visualizer_bands.qml`)**: Drives `visualizer_bands.js` — 32 cava bands folded onto 12 cookie lobes in contiguous groups (one loud band moves exactly one lobe), bass at lobe 0 through treble at the last, the empty and fewer-bands-than-lobes cases that are what actually arrives before cava has produced anything, clamping to 0..1, and the attack/decay envelope rising faster than it falls and converging without overshoot.

## Static Lints

In addition to the QML unit tests, `run_tests.sh` runs static lint checks first:

* **QML import lint (`lint_qml_imports.sh`)**: Fails if any `.qml` under `modules/` references the `Appearance` singleton as a bareword without `import qs.modules.common`. That import is not transitive through `qs.modules.common.widgets`; omitting it throws `ReferenceError: Appearance is not defined` per binding evaluation, and when the missing token feeds a positioner's `spacing`/`margin` the resulting NaN geometry pegs the shell at 100% CPU. A bulk token migration introduced exactly this, so the lint prevents recurrence.
* **QML module directory lint (`lint_qml_module_dirs.py`)**: Requires any directory reached by a relative QML directory import (`import "../some/dir" as Alias`) to be named like a QML module segment - letters, digits and underscore, no hyphens. Quickshell's scanner reads that directory name as a module name and otherwise logs `Module path contains invalid characters for a module name` on every scan. The import still resolves, so this only ever surfaces as log noise, which is why it survives review. Directories loaded dynamically by path (the `nandoroid-*` plugin ports) are unaffected and deliberately not checked.
* **Lockscreen theme lint (`lint_lockscreen_theme.sh`)**: Keeps transient lock colors owned by `MaterialThemeLoader`, verifies that its virtual-environment wrapper preserves wallpaper paths containing spaces, guards the precomputed palette cache/delayed transition, caps the animated palette-role budget, requires the bounded fast color duration, and prevents locking from switching to synthetic Hyprland workspaces. This avoids theme races, animation contention, and persistent compositor/screencopy state corruption.
* **Region selector capture lint (`lint_region_selector_capture.sh`)**: Requires the selector preview and final crop to share the same freshly generated `grim` image, with image caching disabled and visibility gated on decoding. This prevents an independent screencopy from displaying a stale compositor frame.
* **Plugin process lifecycle lint (`lint_plugin_processes.py`)**: Rejects bundled streaming processes with persistent `running` bindings unless they document restart-safe backoff, prevents Docker's known-runaway desktop host from being re-enabled, and keeps package bar entries behind exactly one loader instead of the runaway nested sizing path. This prevents instant-exit respawn loops and multi-gigabyte allocation failures from starving the shell session.
* **Rich text opt-in lint (`lint_rich_text_optin.py`)**: Installed plugin manifests are attacker-controlled and the render site is their only defence — `PluginValidator.js` type-checks `manifest.name` and nothing else, and `Text`'s inherited `Text.AutoText` renders `<img src=…>` smuggled into a manifest field as markup. The lint pins the three halves of the fix, none of which errors at runtime when broken: both `StyledText` definitions (mainline and the plugin design system's copy) must keep `textFormat: Text.PlainText`; every non-PlainText `textFormat` assignment in the tree — including inline ones after `{` or `;` on the same line, which the first version of the pattern was proved to miss — must match a reviewed file→count allowlist in both directions, so a new rich-text site fails until reviewed and a removed one cannot leave slack; and `ConfigTextArea` must keep forcing the Basic Controls style's `PlaceholderText` child to PlainText, since that `Text` lives inside Qt where the `StyledText` default cannot reach and is fed `optionData.placeholder` straight from the manifest. The companion registry-side drift — the vendored `registry_validate.py`'s `VISUAL_CAPABILITIES` losing a surface and letting an overlay-widget entry skip the screenshot requirement — is pinned by `test_registry_validate.py` against `PluginManager.surfaceCapabilities`.
* **Disabled-opacity lint (`lint_disabled_opacity.py`)**: `opacity` composites down the scene graph, so two components in one subtree each expressing the disabled state as `opacity: enabled ? 1 : 0.4` render at 0.16 rather than 0.4 — every line reads as correct on its own, and only the product is wrong. The lint discovers which types dim themselves at their root (rather than listing them, so a new one protects its descendants immediately) and rejects any `enabled`-conditioned opacity nested inside a component whose root type is one of them, plus any nested *instance* of another self-dimming type. Because the discovery reads indentation it would pass vacuously after a reformat, so it first asserts it still finds the three root-level dims it knows about — by file rather than by type name, since the plugin design system ships its own `RippleButton.qml` and a name-level guard stays satisfied by the copy while the mainline one loses its dim. `ConfigSwitch` was the only doubled widget; the other settings controls are rooted on a plain `RowLayout` and dim once.
* **Wallpaper transition catalogue tests (`test_wallpaper_transitions.py`)**: Pin `modules/common/WallpaperTransitions.qml` as the single list of switch transitions — that every catalogued entry names a shader that exists on disk, that the random pool excludes the "no transition" and "random" pseudo-entries, that no consumer (the background, the settings combo, the desktop menu submenu) spells a shader name out again, and that the submenu filters the active transition out of what it offers. The list previously existed three times over and had drifted, so the menu meant to change the transition omitted five of the eight shaders including the one that was running.
* **Widget interaction mode tests (`test_widget_interaction_modes.py`)**: Pin per-widget lock and click-through on `AbstractBackgroundWidget` — that both flags default off (that class sits under every desktop widget in the shell), that the global `background.widgetsLocked` toggle ORs with the per-widget lock rather than replacing it, that `clickThrough` drives `enabled` rather than a Wayland surface mask, that it drives *both* gates (the host's own `MouseArea` and the `contentItem` wrapper every child is parented into, since `MouseArea.enabled` shadows `Item.enabled` and reaches nothing under it), that the wrapper gates on `clickThrough` rather than on the resolved lock and takes no part in sizing, that `PluginWidget` reads both flags from `PluginState` with the manifest as the seed and never assigns them, and that the settings rows exist so a shipped default stays reversible. Every assertion was confirmed to fail under a matching mutation; `WidgetInteractionRuntimeTest.qml` is the behavioural half.
* **Widget interaction runtime tests (`test_widget_interaction_runtime.py`)**: Drive `WidgetInteractionRuntimeTest.qml` under a headless weston with throwaway XDG dirs, failing on any check it reports and on any `Binding loop` in its output. This is what the source contract cannot reach: whether a click over a click-through widget actually lands on the desktop menu behind it, and whether it stops landing on the controls the widget draws for itself — proved on a synthetic `MouseArea` and on the real bundled notes widget's per-note delete button, each with the same click repeated with click-through off as its control. Skips where weston or `qs` is missing, as in CI.
* **Config control write-back tests (`test_config_control_write_back.py`)**: Two halves of one rule — a ranged settings control must not write to the config just because it was built. The source contract sweeps every `ConfigSpinBox`/`ConfigSlider` in the tree (69 across 16 files) and rejects a write-back hung off `onValueChanged`, and pins the widgets' own shape: the user-only `valueModified` signal, the `onTextEdited` (not `onTextChanged`) path for the spin box's text field, the range that widens to admit an out-of-range stored value, and the explicit padding that keeps the editable number off the decrement button. Every assertion was confirmed to fail under a matching mutation. The runtime half drives `ConfigControlWriteBackRuntimeTest.qml` under a headless weston and reads `config.json` back off disk. Skips where weston or `qs` is missing, as in CI.
* **Plugin installer tests (`test_plugin_installer.py`)**: Verify remote package paths cannot be absolute or escape the plugin directory using `..`.
* **Preset tests (`test_presets.py`)**: Verify complete desktop plugin state—including positions and per-plugin options—round-trips through presets, while position-only legacy presets retain options they never captured.
* **Matugen application theme tests (`test_matugen_app_themes.py`)**: Verify Cava, btop, and tmux templates are registered idempotently, generated themes preserve unrelated application settings, and live reload hooks run after Matugen renders.
* **Expressive design-system tests (`test_expressive_design_system.py`)**: Keep the shared Material 3 Expressive library out of the plugin catalog, verify the complete port inventory, and require independent creator-attributed manifests for all six nandoroid desktop widgets.
* **Currency service safety tests (`test_currency_service_contract.py`)**: Require one debounced API request per refresh, stale-response invalidation, a bounded timeout, and a non-reentrant completion path without `XMLHttpRequest.abort()`. This prevents DNS outages or startup setting bindings from multiplying pending network callbacks on Quickshell's UI thread.
* **Cava spectrum contract tests (`test_cava_contract.py`)**: `CavaService` shipped a `refCount`, a `barCount` and a `values` array with no producer behind any of them, so three widgets were written against it and rendered nothing — silently, with a green suite, because the QML tests never build them ([#155](https://github.com/XephyLon/immaterial-impulse/issues/155)). None of that is reachable from a unit test; the shape that allowed it is. The generic check rejects any file declaring a `refCount` without starting a `Process` — a reference count promises something is being started and stopped. The specific ones pin the band count against the `bars` in `scripts/cava/raw_output_config.txt` (the service said 32 while the process emitted 50), the process gate naming both the reference count and an active player so nothing decodes audio for an idle desktop, no consumer carrying its own copy of the 0..1000 range, no hand-written `refCount++`/`--` outside the service and `CavaRef`, and `GlobalStates.visualizerPoints` staying retired — a leftover publication channel still reads as a live band source. Each assertion was confirmed to fail under a matching mutation.
* **Ripple lifecycle safety tests (`test_ripple_lifecycle_contract.py`)**: Require ripple handlers to call their owning component explicitly and stop active animations before delegate destruction. This prevents media-player replacement or configuration reloads from repeatedly invoking functions through invalid QML contexts and stalling the event loop.
* **Event-loop safety tests (`test_event_loop_safety_contract.py`)**: Guard expired notification timers, prevent Loader/item dimension feedback in the bar, and restrict `mirrored` writes to visualizers. These checks cover the binding loops and invalid-object callbacks observed immediately before shell stalls. The module has also accumulated two adjacent UI-contract checks: that the Settings window is floated by its fixed size hints rather than by a runtime `hyprctl eval` rule (which never survives the shell's startup reload), and that the spacing lint covers the grid-gap and axis-padding property names whose spelling let raw literals past it.

* **Dock motion contract tests (`test_dock_motion.py`)**: Require the dock's feedback motion (hover lift, press squish, launch bounce, appear pop, active-dot springs) to be token-driven and shared identically by pinned (`DragApps`) and running (`DockAppButton`) buttons, with `DockLaunchTracker` supplying a timeout-bounded launch-pending state and the wrapper never animating layout size.
* **Screenshot result contract tests (`test_screenshot_result_contract.py`)**: Pin the `ScreenshotEvents` IPC hub's validated `notify`, the generic `PluginPanelHost` that finally instantiates the plugin `panel` entry point, the bundled popup's scratch-dir-guarded discard and argv-only (never shell-spliced) save/edit, and the keybind chain that files-then-copies-then-notifies with `|| true` shell-down tolerance.
* **Momentum scroll contract tests (`test_momentum_scroll_contract.py`)**: Pin `StyledFlickable`'s opt-in inertial trackpad scrolling — finger-lift flick handoff with velocity clamping, discrete mouse-wheel fallback, clamped `contentY` writes, and the fast-scroll path yielding while momentum is active.
* **Keybind cheatsheet parser tests (`test_get_keybinds.py`)**: Drive `get_keybinds.py` against a fixture `keybinds.lua`, pinning section nesting, mod/key/dispatcher/param extraction, `[hidden]` exclusion, exec autodescriptions, and a bind-count canary so a parser regression can't silently empty the `Super`+`/` overlay.
* **Color pipeline tests (`test_lock_palette_parity.py`, `test_scheme_for_image.py`, `test_generate_colors_material.py`)**: Pin that lock-screen color generation produces byte-identical output to the desktop path for the same image (no `--smart`, `auto` resolved via `scheme_for_image.py`), that the detector returns a valid scheme per image, and that the generator emits every color key the shell consumes for both modes. Behavioural parts skip cleanly when `materialyoucolor`/`cv2` are absent.
* **Installer safety tests (`test_installer_file_sync.py`, `test_installer_legacy_migration.py`, `test_installer_greeting_traps.py`)**: Sandbox `3.files.sh`'s `rsync --delete` sync/backup helpers with canary files proving deletion never escapes its target, drive `1.deps-router.sh`'s legacy detection/removal against stubbed package managers (only `illogical-impulse-*` matched, exact `-Rn` set, never cascading), and pin the quiet-install cancel machinery (process-group traps, `set -m`, no `setsid` regression).
* **Status-service and safety contracts (`tst_battery.qml`, `tst_bluetooth_status.qml`, `test_updates_contract.py`, `test_conflict_killer_contract.py`, `test_polkit_service_contract.py`, `test_ydotool_contract.py`, `test_brightness_systeminfo_contract.py`)**: Behaviourally exercise Battery/Bluetooth against new mocks, run the real Updates count pipeline against stubs, and pin the safety envelopes of the silent-failure services — ConflictKiller's exact-name literal kill set (no PID signaling), Polkit's interaction flow, Ydotool's argv-only (no shell splicing) command construction, and Brightness's never-fully-black clamps.
* **Night light state tests (`test_nightlight_state_runtime.py`)**: hyprsunset cannot be asked whether the blue-light filter is applied — `hyprctl hyprsunset temperature` reports the last temperature the daemon was *told*, and `identity` never resets it — so the shell persists on/off itself and re-applies it at startup. These launch the real `Hyprsunset` singleton against a seeded `states.json` and fake `hyprsunset`/`hyprctl`/`pidof` binaries, pinning that `temperatureActive` comes from the state file rather than from the useless query, that the state is *applied* (warm launch flags on a cold daemon, an `hyprctl` correction on a warm one), and that toggling writes straight back to disk. See Runtime harnesses for why `pidof` has to be faked.
* **Note store tests (`tst_notes_store.qml`, `test_notes_store_contract.py`, `test_notes_migration_runtime.py`)**: `tst_notes_store.qml` drives `modules/common/functions/notesStore.js` through every on-disk state the two old note stores can be in — plaintext, a valid array, both at once, either absent, either corrupt, and a scratchpad whose text happens to be JSON that is not notes — pinning that nothing is discarded (unparseable content becomes a note verbatim; the deleted built-in service reset it to `[]`). The contract module pins the single owner (`services/Notes.qml` — neither the plugin widget nor the overlay editor may hold a `FileView`), the migration marker being written after the store, and `textFormat: PlainText` everywhere a note body reaches the screen. `test_notes_migration_runtime.py` is the behavioural half: it launches the real service in a real Quickshell against a throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME`, once per case, and checks both that content in either old store survives and that neither source file is touched.
* **Config-dir / keyring migration and prebuilt-WE installer tests (`test_config_migration.py`, `test_keyring_migration.py`, `test_wallpaperengine_prebuilt.py`)**: Previously shipped but never invoked; now wired into `run_tests.sh`. Cover the `illogical-impulse` → `immaterial-impulse` config-dir move (no-clobber), keyring attribute migration, and the checksum-verified prebuilt Wallpaper Engine fast-path against a fixture release. `test_config_migration.py` since grew the decision the move actually turns on: a `config.json` already in the destination is compared byte-for-byte against the shipped `defaults/config.json`, because the installer seeds that file verbatim and "a config.json exists" was silently disabling the whole migration. Where it cannot tell, the script must change nothing and exit `3` — the tests pin the refusal and its message, not just the happy path. `test_config_dir_migration_runtime.py` is the behavioural half (see Runtime harnesses).
* **Background fullscreen suppression tests (`test_background_fullscreen_suppression.py`)**: Guard the one regression in this repo with a photosensitive-seizure hazard attached — binding the background `PanelWindow`'s own `visible` to a fullscreen condition, which under `WlrLayershell` destroys the layer surface rather than hiding it and strobed the desktop at 30Hz. Unlike every other check here it does not match source text: it blanks comments and string contents, matches braces, and works on the resulting object tree, because the pin it replaces looked for a literal eight-space indent, matched zero lines, and reported green for months (#97). All three routes to the window's `visible` fail — a declarative binding (any binding, not just one naming fullscreen: the likeliest reintroduction is `visible: !bgRoot.suppressContents`, which reads as a simplification), an imperative assignment qualified or bare, and a `Binding` object. `QmlParserTests` pins the parser itself against the shapes that broke its predecessor (grouped properties, `Behavior on X {`, braces inside strings, an `id` followed by an initialiser-less declaration), including a fixture that must still be caught. Ten mutations of the real sources were each confirmed to turn it red; a comment added in the file's own style, a whole-file reindent, and a rewrapped binding were each confirmed to leave it green.

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

`test_discord_voice_plugin.py` verifies private token-cache permissions and RPC
state minimization, requires one bounded bridge with capped restart backoff, and
keeps the clickable Discord bar widget on its native single-owner geometry path.

Its companion-transport cases are behavioral, not textual: they bind a real
socket under a permissive umask to prove the mode comes from the bind rather
than a later `chmod`, drive a hanging `drain()` to prove a wedged companion
cannot stall the bridge, and feed a malformed frame ahead of a valid one to
prove one bad frame does not end the session. Each was confirmed to fail with
its fix reverted — assert the property that matters, not the presence of the
line that implements it.

## Runtime harnesses (repository root)

`CurrencyRuntimeTest.qml`, `DiscordVoiceRuntimeTest.qml`, `DockerRuntimeTest.qml`,
`DockerBarControlRuntimeTest.qml`, and `DockerBarHostRuntimeTest.qml` are
manually launched harnesses, driven by `run_docker_memory_test.sh` via
`quickshell -p <file>`.

`DesignSystemCompile.qml` is run by the suite itself (it needs a compositor, so
it skips without `WAYLAND_DISPLAY`). It compiles every design-system file, every
bundled package entry point, **every settings page**, and the shared widgets
those pages are built from. The settings pages are in that sweep because a
settings page is only ever compiled when the user opens it: a renamed signal
handler or a misspelled property on one of them leaves the whole shell green,
and the `qmltestrunner` suite green too, until somebody clicks that tab.

`WidgetInteractionRuntimeTest.qml` is self-checking and driven from the suite by
`tests/test_widget_interaction_runtime.py`: it builds four real `PluginWidget`s
on a real `WidgetCanvas` and drives per-widget lock and click-through with
actual mouse events, exiting non-zero on any failure. `import QtTest` works
inside `qs -p`, so `TestCase.mouseClick()` delivers real events without
`ydotool` — which is the only way to prove a click over a click-through widget
reaches the desktop area behind it, and stops reaching the widget's own
controls, rather than merely that a property flipped. Two of the four widgets
exist for that second half: one declares a `MouseArea` of its own inside the
host, and one is the real bundled notes widget, whose per-note delete button
calls straight into the `Notes` singleton and so is observable from outside the
widget. Run it by hand against a throwaway config — it writes plugin options,
positions and the note store, and a stale state file from a previous run would
make it start from the wrong defaults:

```bash
XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
  qs -p WidgetInteractionRuntimeTest.qml
```

`ConfigControlWriteBackRuntimeTest.qml` is self-checking and driven by
`tests/test_config_control_write_back.py`. It seeds a throwaway
`XDG_CONFIG_HOME` with `osd.timeout: 4321` — a value the config format accepts
and the shell honours, and one the Sidebars & Panels page's own spin box
declares out of range at `to: 3000` — waits for `Config.ready`, and only *then*
builds the real `SidebarsPanelsConfig`, because that is what the Settings window
does and because building it earlier hides the bug entirely (the page is
constructed against schema defaults and its binding is gone before the file
lands). It asserts the negative, that nothing changed, then scrolls to the
control and clicks its decrement button through `QtTest` to prove it is not
merely inert. Against the unfixed code the same harness turned 4321 into 3000 on
disk. Run it by hand against a throwaway config — it writes `config.json`:

```bash
XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
  qs -p ConfigControlWriteBackRuntimeTest.qml
```

`NotesMigrationRuntimeTest.qml` and `NotesSurfacesRuntimeTest.qml` are
self-checking too, and are likewise driven from the suite —
`tests/test_notes_migration_runtime.py` and `tests/test_notes_surfaces_runtime.py`
launch them and fail on any check they report. The first exercises the note
store migration against real files (one launch per on-disk case, throwaway XDG
dirs). The second builds the bundled notes plugin widget and the overlay notes
editor side by side over one store and clicks their buttons for real, which is
the only way to show that a note added in one surface is in the other and that
the delete button deletes.

`ConfigDirMigrationRuntimeTest.qml` is driven the same way, by
`tests/test_config_dir_migration_runtime.py`. What it proves cannot be reached
from the migration script alone: the `~/.config/illogical-impulse` →
`immaterial-impulse` move has to *finish* before `Config` reads or writes the
destination, and it used to be fired with `Quickshell.execDetached`, which
returns immediately. The harness samples `Directories.configDirReady` at the
instant `Config.ready` turns true, and the driver forces the interleaving that
used to lose rather than hoping to observe it — `IMI_MIGRATE_DELAY` (a seam in
the script, never set in normal operation) holds the migration open for
seconds, which a racing `Config` load wins every single time. The same module
covers the composition with the in-`Config` upstream-key migration (one launch
must both move the directory and convert the keys inside it) and the read-only
watchdog that fires when the migration never finishes. It brings its own
headless weston for the same reason as the surfaces harness below, minus the
window: a test that migrates config directories has no business running against
the caller's session.

`NightLightStateRuntimeTest.qml` is driven by
`tests/test_nightlight_state_runtime.py`, and exists because hyprsunset has no
state query: on 0.4.0 `hyprctl hyprsunset --help` lists only `temperature`,
`identity` and `gamma`, the daemon socket rejects everything else, and the bare
`temperature` request reports the last temperature the daemon was *told* —
which `identity` never resets, so a neutral screen and a warm one report the
same number. The shell therefore persists on/off itself and re-applies it, and
the harness pins both halves: what `Hyprsunset.temperatureActive` comes up as
against a seeded `states.json`, and what the shell actually told the daemon to
do about it. The driver puts fake `hyprsunset`, `hyprctl` and `pidof`
executables at the front of `PATH` and reads their recorded argv back. `pidof`
is the load-bearing fake, not scenery: `startHyprsunset` short-circuits on
`pidof hyprsunset ||`, so on any machine with a live daemon — the developer's
own, invariably — a launch-flag assertion would pass without the launch path
ever running. Faking it makes cold start and warm start both reachable on
purpose, and keeps the suite from ever tinting the caller's screen.

The widget-interaction and surfaces harnesses bring their own **headless weston**
(`weston --backend=headless --renderer=pixman`, plus `LIBGL_ALWAYS_SOFTWARE=1`
and `QT_QUICK_BACKEND=software` — this box's headless EGL has no driver) rather
than using the caller's session, because they open a window and would otherwise
throw one across the user's desktop. Weston implements no wlr-layer-shell, so
nothing that needs a `PanelWindow` can be proved there: both notes surfaces are
ordinary `Item`s, and so are `WidgetCanvas` and the widget tree under it — what
cannot be shown that way is anything about the real `Background.qml` layer
surface itself, such as how it stacks against another surface.

They live at the repository root on purpose and should not be moved into
`tests/`: `quickshell -p` roots the `qs` module at the directory of the file it
is given, so from `tests/` their `import qs.modules.imi.bar` would no longer
resolve. A file loaded by URL only resolves a `qs.*` module that something
already in the loaded tree has imported, which is why
`NotesSurfacesRuntimeTest.qml` imports `qs.modules.imi.overlay` without using a
type from it.
