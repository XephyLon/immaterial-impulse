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

* **Recording bitrate estimate (`tst_record_bitrate.qml`)**: Drives `modules/common/functions/record_bitrate.js`, the bits-per-pixel model behind Settings > Capture's quality hint - anchored on a measured recording (`very_high`, 1554x892 at 60 fps, 8.59 Mbps), the tiers one square-root-of-two step apart, the frame rate capped at the screen's refresh and rounded whole, and an unmeasured screen estimating 0 so the page hides the hint rather than drawing a figure for a screen that does not exist.
* **Color Math (`tst_color_utils.qml`)**: Tests `transparentize`, `solveOverlayColor`, and `applyAlpha` under `ColorUtils.qml`.
* **Config Schema (`tst_config.qml`)**: Validates that all critical settings have correct defaults defined.
* **Audio Device Name Priority (`tst_audio.qml`)**: Validates the priority selection of friendly audio device names (`description` > `nickname` > `"Unknown"`) and application display names.
* **System Stats Parser (`tst_resource_usage.qml`)**: Tests parsing functions for `/proc/meminfo` contents, `df -k` disk usage output, and `nvidia-smi` GPU/VRAM statistics.
* **Live Desktop Entry Resolution (`tst_live_desktop_entry.qml`)**: Tests `LiveDesktopEntry.qml` against a mock `DesktopEntries` (`tests/mocks/Quickshell/DesktopEntries.qml`) that can simulate `applications` populating after the resolver already exists, guarding against the dock's pinned-launcher regression where a `heuristicLookup()`-based binding never refreshed once the desktop entry database finished loading.
* **Music Title Cleanup (`tst_string_utils.qml`)**: Tests `StringUtils.cleanMusicTitle` - strips leading bracketed tags but keeps a fully-bracketed title (e.g. `[BLEED BLOOD]`) instead of blanking the media widget.
* **Battery Transient Swap (`tst_battery.qml`)**: In addition to threshold/health mapping, verifies the battery stays available and freezes its last-good percentage through a transient UPower `displayDevice` swap, so the widget doesn't flap and no false low-battery action fires.
* **Cava band shaping (`tst_cava_bands.qml`)**: Drives `modules/common/functions/cavaBands.js`, the arithmetic that fits the producer's spectrum onto whatever number of bars a consumer draws. Pins that downsampling averages rather than picking one index per bar — the `Math.floor(i * n / barCount)` idiom it replaces reached only 20 of the producer's 50 bands, so a peak landing between two picked indices never appeared — that upsampling interpolates and keeps both ends, that an absent spectrum yields zeros at the requested length rather than a short array, and that levels stay clamped to 0..1 through cava's autosens overshoot. Confirmed to redden under the index-picking implementation it replaces.
* **Per-lobe cookie radii (`tst_rounded_polygon_lobes.qml`)**: Drives `RoundedPolygon.starPerLobe()` — a scalar inner radius is byte-for-byte the old `star()`; an array of twelve radii produces twelve distinct lobes that survive the rounding and reach the built cubics; *which* lobe moved changes the outline (magnitude alone would pass if every lobe read `radii[0]`); and a QML `list<real>` is not mistaken for a scalar. The shapes themselves are not testable here — `qmltestrunner` cannot construct Quickshell types and nothing draws a `Canvas`.
* **Launcher math gate (`tst_math_query.qml`)**: Drives `services/math_query.js`, which decides whether a query is worth spawning `qalc` for *before* anything is spawned. The load-bearing half is the "no": the spawn used to be fired from inside the `results` binding, so every non-prefixed query started a calculator per keystroke (measured: 8 processes for "firefox"). The test walks every prefix of eight application names, because a prefix is what actually gets evaluated while somebody types, and pins the explicit `=` prefix, a configurable or empty prefix, and the shapes that open like arithmetic without being any (`(a+b)`, `-`, `+++`). Confirmed to redden both ways: a gate that accepts everything, and one that rejects everything unprefixed.
* **App launch frecency (`tst_frecency.qml`)**: Drives `services/frecency.js`, the ranking `services/AppUsage.qml` stores and `services/AppSearch.qml` applies. Pins the two properties the feature is for — repeated launches reorder two equally good matches, and no amount of use promotes an app past one matching more than twice as well — plus every way the store can be unusable. A missing, empty or corrupt store parses to `null`, the caller falls back to an empty one, and an empty store makes the boost the identity, so degradation to plain match-order ranking is structural rather than a special case. Also covers a half-written entry not taking its neighbours with it, the per-app and per-store caps, and a clock that moved backwards not turning the most recent launch into the least valuable one.
* **Reorder arithmetic (`tst_layout_ops.qml`)**: Drives `modules/common/functions/layout_ops.js`, the list arithmetic four drag-to-reorder surfaces had each written out locally. The assertion the module exists for is that a drag across three neighbours *shifts* them along rather than exchanging two entries — asserted as the whole expected list, and paired with an explicit check that the swap's answer is a different list, because the two agree for a step of one and any assertion that could pass under either spelling would have passed on the code this replaced. Also pins that an index off the end leaves the list alone rather than punching a hole (the indices come off live `Repeater` items and a list that can reflow mid-gesture), and that `move` copies while `moveInPlace` reorders the array it was handed — both exist because the quick toggles mutate a live `Config` array on purpose, 26b625905 ("Revert \"fix(sidebar): make quick toggle edits actually notify\" and follow-ups") having measured that every mutation form notifies. For `indexAt`: a column is answered on the axis it runs along, and comparing the *other* coordinate is not a subtly wrong reorder but an inert one, since every centre shares it and the answer is whichever slot the loop reached first; and a hole in the centre list is skipped rather than read as the origin, which is what keeps the dragged slot from being its own nearest neighbour. Every assertion was confirmed to redden under a matching mutation of the module.
* **Visualizer band folding (`tst_visualizer_bands.qml`)**: Drives `visualizer_bands.js` — the producer's bands folded onto 12 cookie lobes in contiguous groups (one loud band moves exactly one lobe), bass at lobe 0 through treble at the last, the empty and fewer-bands-than-lobes cases that are what actually arrives before cava has produced anything, clamping to 0..1, and the attack/decay envelope rising faster than it falls and converging without overshoot.

## Static Lints

In addition to the QML unit tests, `run_tests.sh` runs static lint checks first:

* **QML import lint (`lint_qml_imports.sh`)**: Fails if any `.qml` under `modules/` references the `Appearance` singleton as a bareword without `import qs.modules.common`. That import is not transitive through `qs.modules.common.widgets`; omitting it throws `ReferenceError: Appearance is not defined` per binding evaluation, and when the missing token feeds a positioner's `spacing`/`margin` the resulting NaN geometry pegs the shell at 100% CPU. A bulk token migration introduced exactly this, so the lint prevents recurrence.
* **Reorder-arithmetic lint (`lint_reorder_arithmetic.py`)**: A drag that reorders a list must reorder it through `modules/common/functions/layout_ops.js`. Four surfaces had written that arithmetic out for themselves, and the defect was not the duplication but the disagreement: `LayoutSection` and `DocktoPanel` took the dragged item out and put it back at the drop index, while `DragApps` and `AndroidQuickToggleButton` exchanged the two entries, so a drag across three neighbours displaced exactly one of them. Both spell the same list for a step of one, which is why nobody saw it. The scope comes from the tree rather than a file list — a QML file declaring a `DragHandler` is a file where something is dragged — and inside one, three idioms are refused: a splice-out immediately followed by a splice-in (`move`, spelled locally), an indexed element exchange (the swap), and a `minDist`/`Infinity` accumulator beside a distance expression (`indexAt`, spelled locally). Scoping by gesture rather than by name is what leaves `DesktopContextMenu.qml`'s Fisher-Yates wallpaper shuffle — a legitimate use of the second idiom — alone without an allowlist to maintain. The four sites are named only as a floor: if one stops declaring a `DragHandler`, moves, or stops reaching the module, the lint fails rather than sweeping an empty scope. It self-checks against in-memory fixtures before it sweeps, and was confirmed to report all twelve violations across the four files on the tree it was written against. The behavioural half is `DockEdgeRuntimeTest.qml`'s last gesture: every drag in that harness stepped one slot at a time, and a run of adjacent swaps is a move, so the file would have stayed green under either spelling — the added gesture arms the grab and then jumps two slots in one event, which is what a pointer outrunning the event stream does on a real dock, and it reddens under the swap it replaced while the four older checks do not.
* **QML module directory lint (`lint_qml_module_dirs.py`)**: Requires any directory reached by a relative QML directory import (`import "../some/dir" as Alias`) to be named like a QML module segment - letters, digits and underscore, no hyphens. Quickshell's scanner reads that directory name as a module name and otherwise logs `Module path contains invalid characters for a module name` on every scan. The import still resolves, so this only ever surfaces as log noise, which is why it survives review. Directories loaded dynamically by path (the `nandoroid-*` plugin ports) are unaffected and deliberately not checked.
* **Lockscreen theme lint (`lint_lockscreen_theme.sh`)**: Keeps transient lock colors owned by `MaterialThemeLoader`, verifies that its virtual-environment wrapper preserves wallpaper paths containing spaces, guards the precomputed palette cache/delayed transition, caps the animated palette-role budget, requires the bounded fast color duration, and prevents locking from switching to synthetic Hyprland workspaces. This avoids theme races, animation contention, and persistent compositor/screencopy state corruption.
* **Region selector capture lint (`lint_region_selector_capture.sh`)**: Requires the selector preview and final crop to share the same freshly generated `grim` image, with image caching disabled and visibility gated on decoding. This prevents an independent screencopy from displaying a stale compositor frame.
* **Plugin process lifecycle lint (`lint_plugin_processes.py`)**: Rejects bundled streaming processes with persistent `running` bindings unless they document restart-safe backoff, prevents Docker's known-runaway desktop host from being re-enabled, and keeps package bar entries behind exactly one loader instead of the runaway nested sizing path. This prevents instant-exit respawn loops and multi-gigabyte allocation failures from starving the shell session.
* **Rich text opt-in lint (`lint_rich_text_optin.py`)**: Installed plugin manifests are attacker-controlled and the render site is their only defence — `PluginValidator.js` type-checks `manifest.name` and nothing else, and `Text`'s inherited `Text.AutoText` renders `<img src=…>` smuggled into a manifest field as markup. The lint pins the three halves of the fix, none of which errors at runtime when broken: both `StyledText` definitions (mainline and the plugin design system's copy) must keep `textFormat: Text.PlainText`; every non-PlainText `textFormat` assignment in the tree — including inline ones after `{` or `;` on the same line, which the first version of the pattern was proved to miss — must match a reviewed file→count allowlist in both directions, so a new rich-text site fails until reviewed and a removed one cannot leave slack; and `ConfigTextArea` must keep forcing the Basic Controls style's `PlaceholderText` child to PlainText, since that `Text` lives inside Qt where the `StyledText` default cannot reach and is fed `optionData.placeholder` straight from the manifest. The companion registry-side drift — the vendored `registry_validate.py`'s `VISUAL_CAPABILITIES` losing a surface and letting an overlay-widget entry skip the screenshot requirement — is pinned by `test_registry_validate.py` against `PluginManager.surfaceCapabilities`.
* **Disabled-opacity lint (`lint_disabled_opacity.py`)**: `opacity` composites down the scene graph, so two components in one subtree each expressing the disabled state as `opacity: enabled ? 1 : 0.4` render at 0.16 rather than 0.4 — every line reads as correct on its own, and only the product is wrong. The lint discovers which types dim themselves at their root (rather than listing them, so a new one protects its descendants immediately) and rejects any `enabled`-conditioned opacity nested inside a component whose root type is one of them, plus any nested *instance* of another self-dimming type. Because the discovery reads indentation it would pass vacuously after a reformat, so it first asserts it still finds the three root-level dims it knows about — by file rather than by type name, since the plugin design system ships its own `RippleButton.qml` and a name-level guard stays satisfied by the copy while the mainline one loses its dim. `ConfigSwitch` was the only doubled widget; the other settings controls are rooted on a plain `RowLayout` and dim once.
* **Harness check-count lint (`lint_harness_check_counts.py`)**: A runtime harness used to end with `failures: ${harness.failures}` and its driver with `assertIn("[Tag] failures: 0", output)`, and nothing in that pair tells "every check passed" apart from "no check ran" — a loop that stops iterating, a step array that loses an entry, or an early return past the rest of the list all print `failures: 0` and pass. The lint holds both halves of the convention that replaced it: a harness printing a `failures:` verdict must print `checks:` in the same line from a counter incremented inside its own `check()` (a constant, or a counter bumped somewhere else, is a number that survives the harness giving up early), and a driver asserting that verdict must carry the expected count as an interpolated literal rather than reading it back out of the harness's own output. It self-checks against fixtures held in the file before it sweeps, so the machinery is proven independently of what the tree contains.
* **Shader path lint (`lint_shader_paths.py`)**: Every shader path a QML file names as a static literal — `Quickshell.shellPath("….glsl")`, resolved against the shell root, and `Qt.resolvedUrl("….frag.qsb")` or a bare `fragmentShader:`/`vertexShader:` literal, resolved against the declaring file's own directory — must exist on disk. `HyprlandAntiFlashbangShader.qml` named `anti-flashbang-weak.glsl` for the whole life of the file with no such file in the tree, and the first click of the anti-flashbang quick toggle handed that path to Hyprland's `decoration:screen_shader`: Hyprland destroys the previous shader *before* it checks the path, so the effect goes off, complains with a persistent red banner on the focused monitor rather than a log line, and goes on answering `hyprctl getoption` with the path and `set: true` — so the toggle's own label read "Anti-flash: Weak" over a screen with no shader. A missing `.frag.qsb` is the same hole seen as a `ShaderEffect` that draws nothing. Paths built from a template (`Background.qml`'s `shaders/${currentShader}.frag.qsb`) cannot be resolved statically; they are counted and reported rather than ignored, and the catalogue behind them is checked against the same directory by `test_wallpaper_transitions.py`. The lint self-checks against an in-memory fixture carrying all three recognised forms twice — once at a file that exists, once at a file that does not — so a pattern that has stopped matching fails there instead of passing vacuously over a clean tree.
* **Appearance token lint (`lint_appearance_tokens.py`)**: An `Appearance.*` token a QML file reads must be declared in `modules/common/Appearance.qml`. `Appearance.rounding.button`, `.card` and `.extraLarge` were read by six design-system call sites from the day that library was ported and were never declared, and nothing in the suite could see it: an undeclared read is `undefined`, which is a value rather than an error, so `radius: undefined` renders **0** after a single `Unable to assign [undefined] to double` at binding evaluation — a square corner that reads as a design choice — while a call site doing *arithmetic* on the token gets **NaN**, which is a legal double that nothing rejects, nothing logs, and `Math.max(0, x)` does not repair. The QML tests instantiate pure-logic singletons and `DesignSystemCompile.qml` only *compiles* components, and a binding is evaluated by neither, so both stay green throughout. The lint parses `Appearance.qml` into a nested tree (a group is a property whose value is a `QtObject`) and walks every `Appearance.` chain against it, which is what makes its carve-outs fall out of the data rather than an allowlist: resolution stops at a leaf, so `.numberAnimation.createObject(this)` is Qt's API and out of scope; a dynamically-built member (`Appearance.rounding[rName]`, `Appearance.colors["col" + name]`) still resolves its *group* but is counted and reported rather than guessed at; a member may be a `function` as well as a `property`, which the first version got wrong and its own self-check caught; and comments and string bodies are stripped so prose naming a token is not a read. Its first run over the tree found the other twelve names the same port left behind, in the colour and size groups — those sit in a `QUARANTINE` register rather than being silenced with a plausible number, and the register cannot rot, since a name absent from it fails and a name in it that has since been declared also fails. A self-check over an in-memory fixture runs first, and the sweep refuses to pass if it resolved no references or parsed no declarations. `tst_spacing_scale.qml` is the value half: the lint guarantees a token exists, and that pins the ladder's numbers and pins the three M3-named tokens as aliases of the tiers they claim.
* **Wallpaper transition catalogue tests (`test_wallpaper_transitions.py`)**: Pin `modules/common/WallpaperTransitions.qml` as the single list of switch transitions — that every catalogued entry names a shader that exists on disk, that the random pool excludes the "no transition" and "random" pseudo-entries, that no consumer (the background, the settings combo, the desktop menu submenu) spells a shader name out again, and that the submenu filters the active transition out of what it offers. The list previously existed three times over and had drifted, so the menu meant to change the transition omitted five of the eight shaders including the one that was running.
* **Widget interaction mode tests (`test_widget_interaction_modes.py`)**: Pin per-widget lock and click-through on `AbstractBackgroundWidget` — that both flags default off (that class sits under every desktop widget in the shell), that the global `background.widgetsLocked` toggle ORs with the per-widget lock rather than replacing it, that `clickThrough` drives `enabled` rather than a Wayland surface mask, that it drives *both* gates (the host's own `MouseArea` and the `contentItem` wrapper every child is parented into, since `MouseArea.enabled` shadows `Item.enabled` and reaches nothing under it), that the wrapper gates on `clickThrough` rather than on the resolved lock and takes no part in sizing, that `PluginWidget` reads both flags from `PluginState` with the manifest as the seed and never assigns them, and that the settings rows exist so a shipped default stays reversible. Every assertion was confirmed to fail under a matching mutation; `WidgetInteractionRuntimeTest.qml` is the behavioural half.
* **Widget interaction runtime tests (`test_widget_interaction_runtime.py`)**: Drive `WidgetInteractionRuntimeTest.qml` under a headless weston with throwaway XDG dirs, failing on any check it reports and on any `Binding loop` in its output. This is what the source contract cannot reach: whether a click over a click-through widget actually lands on the desktop menu behind it, and whether it stops landing on the controls the widget draws for itself — proved on a synthetic `MouseArea` and on the real bundled notes widget's per-note delete button, each with the same click repeated with click-through off as its control. Skips where weston or `qs` is missing, as in CI.
* **OpenRGB streamer tests (`test_openrgb_stream.py`)**: A fake SDK server on a loopback port serves controller descriptions and records what `scripts/rgb/openrgb_stream.py` sends: the mode command once per controller at connect and never to one already in Direct (it is the command that blinks), then one UpdateLEDs frame per streaming controller per tick and none once the colour has arrived, a new target reached as a ramp, name and type exclusions never written to, and the wire format RGBController.cpp parses. Stdlib only; no OpenRGB needed.

* **Settings row grammar tests (`test_settings_row_grammar.py`)**: The row shapes Settings > Capture is the reference page for (AGENT.md's design-language section): the six widgets that carry them - `CatalogueRow`, `ConfigSwitch`, `ConfigSelectionArray`, `ConfigComboBox`, `ConfigTextArea`, `ContentSubsection` - declare each piece as an opt-in, read `Appearance` for every radius, font size and colour, write no duration or easing, and take every `Behavior`'s tier from its factory; and the page uses every piece - a plain icon on every toggle row (the chip behind it was retired on 2026-08-30; the same test refuses `iconChip` anywhere under `modules/`), an icon on every option, the quality hint computed through `record_bitrate.js` from `HyprlandData.monitors` with no placeholder screen, one recommended codec, floating labels on every field, an icon on every subsection, and rationale on the (i) rather than in a paragraph. A page adopting the grammar later is pinned here.
* **Config control write-back tests (`test_config_control_write_back.py`)**: Two halves of one rule — a ranged settings control must not write to the config just because it was built. The source contract sweeps every `ConfigSpinBox`/`ConfigSlider` in the tree (69 across 16 files) and rejects a write-back hung off `onValueChanged`, and pins the widgets' own shape: the user-only `valueModified` signal, the `onTextEdited` (not `onTextChanged`) path for the spin box's text field, the range that widens to admit an out-of-range stored value, and the explicit padding that keeps the editable number off the decrement button. Every assertion was confirmed to fail under a matching mutation. The runtime half drives `ConfigControlWriteBackRuntimeTest.qml` under a headless weston and reads `config.json` back off disk. Skips where weston or `qs` is missing, as in CI.
* **Launcher result-input observation check (`test_launcher_result_inputs.py`)**: `LauncherSearch.results` is a plain property rebuilt through `Qt.callLater` rather than a live binding, which trades one rebuild per input change for one per turn of the event loop — and gives up QML's automatic dependency tracking to get it. `resultInputs` is the hand-written replacement, and a source missing from it is silent: the list simply stops refreshing when that source answers, which for the asynchronous ones (the fd scan, the desktop-entry registry populating seconds after startup, fourteen settings-keyword greps, qalc) is the entire reason to observe them. The check requires every singleton `buildResults()` names to be named by the tracker too, or listed in a reviewed exemption with a reason — the decision it exists to force rather than to make. It self-checks against two in-memory fixtures before it reads the tree, and was confirmed to redden when a source is dropped from the tracker.
* **Plugin installer tests (`test_plugin_installer.py`)**: Verify remote package paths cannot be absolute or escape the plugin directory using `..`.
* **Selective preset tests (`tst_preset_groups.qml`, `test_presets_apply_only.py`)**: the Apply popup's partition table - every preset key claimed, `apps` alone in the never-preselected commands group - and the script's `--only` filtering run against the real presets.sh in a temp HOME: named sections apply, unnamed keep live values, `_pluginState` only when asked, one bad spec refuses without writing, and no `--only` reproduces today's full apply.
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
* **Dumb-widget lint (`lint_dumb_widgets.py`)**: A shared widget is presentational. Every file in `modules/common/widgets` and every component the Components gallery catalogues is scanned, comments stripped, for a service singleton (anything under `services/` except `Translation`), a `Config.options` read, a `GlobalStates` read or write, or a `Process`/`execDetached` - and fails on any of them, with the fix spelled out: move the file to its consumer, or turn the call into a signal and the read into a property the host answers. Two exclusions remain, each with its reason (the notification seam, the popup protocol), and two further checks keep that list honest: an entry that no longer offends must be deleted, and an entry naming a file that has left the folder must be deleted. Mutation-checked against a `GlobalStates` read planted in a catalogued row.
* **Component gallery lint (`lint_component_gallery.py`)**: Every `RippleButton` descendant in the shell is either catalogued in `CheatsheetComponents.qml` or excluded with a reason, every catalogued path exists, and every entry's `toggles:` claim matches its type - a toggle HAS the property (a `RippleButton` descendant, or a type declaring its own) AND reads it; inheriting alone put a dead switch on 46 pages, the word alone put a broken one on two composites. Entries are read as balanced `{...}` objects and the array's shape is checked between them, because the first version of the claim lint was satisfied by a `toggles: true` that had landed outside its entry - a syntax error that took the whole tab down while the lint stayed green.
* **Bar popup slot tests (`tst_bar_popup_slot.qml`)**: The rules for which of the bar's ten popups gets its one shared card, as a pure function in `modules/common/functions/bar_popup_slot.js`: an empty slot is granted, a hover takes the card from an unpinned neighbour, a pinned occupant holds it against a hover, a second deliberate click outranks the first, Edit Mode refuses every claim including the one already holding, and holding already is not a swap. Plus the other half of a handover - when the outgoing popup drops its hover grace. Lives in a `.js` because the QML suite substitutes a double for `GlobalStates`, and a rule written there would be tested through a copy of itself.

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

Two modules are the exception to "static assertions over source text", and both
are named here so the paragraph above is not read as covering everything.
`test_phone_scrcpy_manager.py` drives `scripts/phone/scrcpy_session_manager.py`
over its real stdin/stdout with fake `scrcpy`/`adb`/`hyprctl` on PATH, and
`test_phone_shell_scripts.py` runs the Phone tab's four shell scripts with
stubbed `pgrep`, `pactl`, `v4l2-ctl`, `droidcam-cli`, `scrcpy` and `sudo`. In
the second the stubs are the process TABLE and the sound server only: the
processes are launched through `droidcam_session.sh launch` and are real, with
real pids and real `/proc/<pid>/cmdline`, so the signature matching, the port
disambiguation and the kill guard run against what they run against in
production. `droidcam-cli` cannot run on this machine at all (built against
ffmpeg 8, the system has 9), which is the other half of why the fakes are fakes.

Every defect check in those two has a green CONTROL beside it - the microphone
is still found by its own name, a four-digit port still reads, a teardown leaves
an unrelated sink alone - because a check that only ever sees the working case
passes on the defect, and one that only ever sees the broken case cannot tell a
fix from a feature that stopped working.

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

Every harness here reports the same verdict — ``[Tag] checks: N failures: M`` — and the count is the load-bearing half. `failures: 0` is what a harness that ran *nothing* prints too, so each driver asserts the whole line with the expected `N` written out as a literal it holds itself; deleting a step from a harness's list reddens its driver instead of quietly shrinking the suite. The counter is incremented inside `check()`, so a harness that gives up part-way reports what it reached rather than what it meant to run. `tests/lint_harness_check_counts.py` fails the suite on a harness or a driver that leaves either half out.

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

`LauncherQalcRuntimeTest.qml` (driven by `tests/test_launcher_qalc_runtime.py`,
headless weston, in `run_tests.sh`) counts the `qalc` processes a typed query
really starts, with a counting stub named `qalc` first on `PATH`. A unit test
can check the gate's predicate and would go on passing if the launcher never
consulted it; how many times the *call site* fires is a property of the binding
graph and needs a real shell. Its two cases are a pair on purpose — "zero
processes" is also what a harness that never typed reports — so the math query
runs as the control, and the harness checks that the whole query arrived and
that the `results` binding was live before it reports a count at all.

`AppUsageRuntimeTest.qml` (driven by `tests/test_app_usage_runtime.py`, headless
weston, in `run_tests.sh`) writes and reads a real launch-history store under a
throwaway `XDG_STATE_HOME`, and ranks the machine's own desktop entries through
it. Three things live there that `tst_frecency.qml` cannot reach: a launch
recorded in one shell is still there in the next, the ranking is actually wired
to the store (`AppSearch` would pass every unit test while ignoring `AppUsage`
entirely), and a corrupt file on disk degrades to plain match-order ranking
rather than breaking search. The record case looks for a query whose first two
results are close enough that the capped boost can overturn them, rather than
assuming the first query it tries produces one.

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

`WidgetResizeGripRuntimeTest.qml` and `WidgetResizeMotionRuntimeTest.qml` split one
feature between them, and the split is the point. The grip harness
(`tests/test_widget_resize_grip_runtime.py`) drags the corner of two real
`PluginWidget`s — one offering three spans, one offering a single one as the
control — and scores only **settled** sizes plus the widget's position, because
its question is whether the corner resizes the widget or *walks* it. That leaves
it blind to whether the resize is animated at all: a `Behavior` handed a target
that moves every frame compiles, never ticks, and snaps the property to its final
value, which is how the parallax opt-out shipped inert. So the motion harness
(`tests/test_widget_resize_motion_runtime.py`) samples the size 80ms and 240ms
**into** a span change and fails if it was already at the destination, if it had
not left the old span, or if the two samples agree — driving both the Size row's
single write and a live grip drag, since only the second re-writes the target on
every mouse move. It also scores the three things a settled size cannot show: that
the content's span name is still the old one early and the new one past the
midpoint (read off `PluginNode`, not off the host property feeding it — reading the
latter passed while the pop was back), that a widget grown flush with the right
screen edge ends up inside the screen with its stored position agreeing, and that
Escape returns the size on a move rather than a snap. Both write plugin state, so
run them by hand against a throwaway config:

```bash
XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
  qs -p WidgetResizeMotionRuntimeTest.qml
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
