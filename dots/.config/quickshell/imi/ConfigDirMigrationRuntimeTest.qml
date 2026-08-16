import QtQuick
import Quickshell
import qs.modules.common

/**
 * Drives the config-directory migration and Config's own load in one real
 * Quickshell process, and reports which of the two got there first.
 *
 * tests/test_config_migration.py drives scripts/migrate-config-dir.sh on its
 * own, which can only ever prove what the script decides from what is on disk.
 * The bug this harness exists for is not in that decision - it is that the
 * script used to be fired with `Quickshell.execDetached`, which returns
 * immediately, so Config's asynchronous FileView load ran concurrently with it
 * and could write a default config.json into the destination first. The
 * migration then found a config.json there and skipped the entire directory.
 *
 * So the property under test is an ordering: at the moment `Config.ready`
 * turns true, `Directories.configDirReady` must already be true. The driver
 * forces the interleaving that used to lose by setting IMI_MIGRATE_DELAY,
 * which holds the script open for seconds - long enough that a Config load
 * racing it would win every time.
 *
 * Launched once per case by tests/test_config_dir_migration_runtime.py, which
 * seeds a throwaway XDG_CONFIG_HOME and checks the files afterwards. Never
 * point it at a real config directory - it migrates and writes one.
 *
 *   CONFIGDIR_EXPECT='{"osd.timeout": 1700}' XDG_CONFIG_HOME=$(mktemp -d) \
 *     XDG_STATE_HOME=$(mktemp -d) qs -p ConfigDirMigrationRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property double startedAt: Date.now()

    property bool seenConfigReady: false
    property bool dirReadyBeforeConfig: false
    property int configReadyAfterMs: -1
    property int dirReadyAfterMs: -1

    readonly property var expected: JSON.parse(Quickshell.env("CONFIGDIR_EXPECT") ?? "{}")

    // "gated": the migration is expected to finish first, which is the whole
    // point. "watchdog": the migration is expected to still be running when
    // Config's watchdog gives up on it, which must produce a shell that reads
    // the config but never writes it.
    readonly property string mode: Quickshell.env("CONFIGDIR_MODE") ?? "gated"

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[ConfigDirMigration] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function optionAt(path) {
        let node = Config.options;
        for (const part of path.split(".")) {
            if (node === undefined || node === null)
                return undefined;
            node = node[part];
        }
        return node;
    }

    function noteConfigReady() {
        if (harness.seenConfigReady || !Config.ready)
            return;
        harness.seenConfigReady = true;
        harness.configReadyAfterMs = Date.now() - harness.startedAt;
        // The whole point: sampled at the instant Config first has a config,
        // not afterwards, when the migration would have caught up anyway.
        harness.dirReadyBeforeConfig = Directories.configDirReady === true;
    }

    function finish() {
        console.log(`[ConfigDirMigration] migration finished after ${harness.dirReadyAfterMs}ms, Config ready after ${harness.configReadyAfterMs}ms`);
        console.log(`[ConfigDirMigration] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            harness.noteConfigReady();
        }
    }

    Connections {
        target: Directories
        function onConfigDirReadyChanged() {
            if (harness.dirReadyAfterMs < 0 && Directories.configDirReady === true)
                harness.dirReadyAfterMs = Date.now() - harness.startedAt;
        }
    }

    Component.onCompleted: {
        if (Directories.configDirReady === true && harness.dirReadyAfterMs < 0)
            harness.dirReadyAfterMs = 0;
        harness.noteConfigReady();
    }

    Timer {
        id: waitForConfig
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForConfig.interval;
            harness.noteConfigReady();
            if (!Config.ready) {
                if (harness.elapsed >= 30000) {
                    harness.check("Config becomes ready", false);
                    harness.finish();
                }
                return;
            }
            waitForConfig.running = false;

            if (harness.mode === "watchdog") {
                harness.check("the watchdog released Config without waiting forever",
                              !harness.dirReadyBeforeConfig);
                harness.check("and released it read-only", Config.configDirTimedOut === true);
            } else {
                harness.check("the config dir migration completed before Config read the directory",
                              harness.dirReadyBeforeConfig);
                harness.check("and left writes enabled", Config.configDirTimedOut === false);
            }
            for (const path in harness.expected) {
                const actual = harness.optionAt(path);
                harness.check(`${path} is ${JSON.stringify(harness.expected[path])}, got ${JSON.stringify(actual)}`,
                              actual === harness.expected[path]);
            }

            // Config writes are debounced, and the upstream-key migration only
            // runs once the file has loaded - give both a moment to land before
            // the driver reads the file back.
            settle.running = true;
        }
    }

    Timer {
        id: settle
        interval: 1000
        onTriggered: harness.finish()
    }
}
