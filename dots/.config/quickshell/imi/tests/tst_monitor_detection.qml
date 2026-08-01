import QtTest
import "../modules/common/functions/monitorDetection.js" as MonitorDetection

// Connector-name heuristics behind the auto keep-awake-on-external-monitor
// option (Config.options.idleInhibitor.autoOnExternalMonitor, consumed by
// services/Idle.qml). Ported from end-4/dots-hyprland PR #2109; the pattern
// expectations below intentionally pin the upstream semantics, including the
// DP-N-M-counts-as-built-in caveat.
TestCase {
    name: "MonitorDetectionTest"

    function test_builtInPanelNamesAreNotExternal() {
        compare(MonitorDetection.isBuiltIn("eDP-1"), true);
        compare(MonitorDetection.isBuiltIn("eDP-2"), true);
        compare(MonitorDetection.isBuiltIn("LVDS-1"), true);
        compare(MonitorDetection.isBuiltIn("DSI-1"), true);
        // Upstream treats DP-N-M as "some integrated displays".
        compare(MonitorDetection.isBuiltIn("DP-1-2"), true);
    }

    function test_commonExternalConnectorsAreExternal() {
        compare(MonitorDetection.isBuiltIn("DP-1"), false);
        compare(MonitorDetection.isBuiltIn("DP-3"), false);
        compare(MonitorDetection.isBuiltIn("HDMI-A-1"), false);
        compare(MonitorDetection.isBuiltIn("DVI-D-1"), false);
    }

    function test_laptopAloneHasNoExternal() {
        compare(MonitorDetection.hasExternal(["eDP-1"]), false);
    }

    function test_laptopPlusExternalIsDetected() {
        compare(MonitorDetection.hasExternal(["eDP-1", "HDMI-A-1"]), true);
        compare(MonitorDetection.hasExternal(["eDP-1", "DP-2"]), true);
    }

    function test_desktopMonitorsCountAsExternal() {
        // Upstream semantics: with no built-in panel, every monitor is
        // "external" - the config option is opt-in for this reason.
        compare(MonitorDetection.hasExternal(["DP-1"]), true);
    }

    function test_multipleBuiltInStylePanelsStayNonExternal() {
        compare(MonitorDetection.hasExternal(["eDP-1", "DP-1-2"]), false);
    }

    function test_emptyAndMissingListsAreSafe() {
        compare(MonitorDetection.hasExternal([]), false);
        compare(MonitorDetection.hasExternal(null), false);
        compare(MonitorDetection.hasExternal(undefined), false);
        compare(MonitorDetection.isBuiltIn(null), false);
    }
}
