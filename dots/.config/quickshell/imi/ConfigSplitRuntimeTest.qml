import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The appearance domain on its own file, in a real shell
 * (docs/proposals/config-storage-split.md, stage 1). Seeded by
 * tests/test_config_split_runtime.py with a config.json carrying an
 * appearance value; checks that the shell reads it, splits it into
 * config.d/appearance.json once, writes appearance changes there and not
 * into config.json, keeps every other domain in config.json, and that
 * setNestedValue and the generic reads still walk `Config.options`.
 * A second mode (CONFIGSPLIT_MODE=existing) starts with an appearance.json
 * already present and a stale copy in config.json, and expects the file
 * to win.
 */
ShellRoot {
    id: harness
    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property int step: 0
    readonly property string mode: Quickshell.env("CONFIGSPLIT_MODE") ?? "split"

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[ConfigSplit] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }
    function finish() {
        console.log(`[ConfigSplit] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            harness.elapsed += interval;
            if (harness.elapsed > 30000) { harness.check("finished in time", false); harness.finish(); return; }
            if (!Config.ready) return;
            switch (harness.step) {
            case 0:
                console.log(`[ConfigSplit] readyAfterMs: ${harness.elapsed}`);
                if (harness.mode === "existing") {
                    harness.check("an existing appearance.json wins over config.json's stale copy",
                        Config.options.appearance.iconTheme === "from-the-split-file");
                } else if (harness.mode === "unmarked") {
                    // An arriving upstream config: migrateUpstreamKeys writes
                    // before ready, and the split must still copy first.
                    harness.check("the seeded appearance value is read", Config.options.appearance.iconTheme === "probe-theme");
                    harness.check("the upstream marker was set by the migration", Config.options.migratedUpstreamSchema === true);
                } else {
                    harness.check("the seeded appearance value is read", Config.options.appearance.iconTheme === "probe-theme");
                }
                harness.check("the other domains still read", Config.options.osd.timeout === 1700 && Config.options.panelFamily === "imi");
                harness.check("options enumerates every domain",
                    Object.keys(Config.options).indexOf("appearance") !== -1 && Object.keys(Config.options).indexOf("bar") !== -1);
                // A write into appearance, and one into another domain.
                Config.options.appearance.fakeScreenRounding = 1;
                Config.setNestedValue("appearance.extraBackgroundTint", "false");
                Config.options.osd.timeout = 1900;
                harness.check("setNestedValue walks the aggregator", Config.options.appearance.extraBackgroundTint === false);
                harness.step = 1;
                break;
            case 1:
                if (harness.elapsed < 2500) return; // past the write debounce, twice over
                harness.finish();
                break;
            }
        }
    }
}
