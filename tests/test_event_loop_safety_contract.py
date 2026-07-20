import re
from pathlib import Path


def test_removed_notification_timer_is_a_noop():
    source = Path("services/Notifications.qml").read_text()
    guard = source.index("if (!notifObject)")
    dereference = source.index("if (notifObject.isTransient)")
    assert guard < dereference
    # Whitespace-tolerant: the contract is the early return, not its indentation.
    assert re.search(r"destroy\(\);\s*return;", source[guard:dereference])


def test_system_icon_loader_has_no_item_size_feedback_loop():
    source = Path("modules/ii/bar/SystemIcons.qml").read_text()
    assert "width: active ? item?.implicitWidth" not in source
    assert "height: active ? item?.implicitHeight" not in source
    assert "implicitWidth: active ? item?.implicitWidth" not in source
    assert "implicitHeight: active ? item?.implicitHeight" not in source


def test_system_icons_use_stable_implicit_layout_geometry():
    source = Path("modules/ii/bar/SystemIcons.qml").read_text()
    assert re.search(r"GridLayout\s*\{\s*id:\s*flow\b", source)
    assert "columns: root.vertical ? 1 : -1" in source
    assert not re.search(r"\bFlow\s*\{\s*id:\s*flow\b", source)


def test_bar_only_assigns_mirrored_to_visualizers():
    source = Path("modules/ii/bar/BarContent.qml").read_text()
    assert 'hasOwnProperty("mirrored")' not in source
    assert source.count('modelData === "visualizer"') >= source.count("item.mirrored =")


def test_keyboard_indicator_honors_container_theme_color():
    source = Path("modules/ii/bar/HyprlandXkbIndicator.qml").read_text()
    assert "property color color:" in source
    assert "color: root.color" in source
    assert "color: Appearance.colors.colOnLayer0" not in source


def test_plugin_blur_is_bounded_to_widget_geometry():
    source = Path("modules/common/plugins/PluginWidget.qml").read_text()
    image = source[source.index("id: wallpaperSample"):source.index("Rectangle {", source.index("id: wallpaperSample"))]
    assert "anchors.fill: parent" in image
    assert "sourceClipRect: Qt.rect(" in image
    assert "wallpaperMetadata.sourceSize.width" in image
    assert "width: rootWidget.scaledScreenWidth" not in image
    assert "height: rootWidget.scaledScreenHeight" not in image
    assert "x: -rootWidget.x" not in image


def test_popups_wait_for_target_window_before_mapping():
    source = Path("modules/common/widgets/StyledPopup.qml").read_text()
    # The window must outlive hover transitions: it is created on first show
    # and then only its visibility changes, so the pointer crossing the bar-to-
    # popup gap cannot destroy and recreate a layer-shell surface.
    assert "active: everShown" in source
    assert "onPopupVisibleChanged: if (popupVisible) everShown = true" in source
    assert "visible: root.popupVisible" in source
    assert "targetHovered: hoverTarget?.containsMouse" in source
    # Map through the target's window, never the popup's own, and assign the
    # result imperatively so margins never feed back into their own input.
    assert "root.hoverTarget.QsWindow.mapFromItem(" in source
    assert "root.QsWindow?.mapFromItem(" not in source
    assert "readonly property real centerOffsetX" not in source
    assert "function schedulePosition() { positionTimer.restart() }" in source
    assert "onVisibleChanged: if (visible) schedulePosition()" in source
    assert "interval: 180" in source
    assert "onHoveredChanged: root.popupHovered = hovered" in source
    assert "property Timer hoverCloseTimer: Timer" in source
    assert "onTriggered: root.hoverHeld = false" in source


def test_calendar_popup_avoids_layout_and_filter_binding_loops():
    source = Path("modules/ii/bar/ClockWidgetPopup.qml").read_text()
    assert "QtQuick.Layouts" not in source
    assert "ColumnLayout" not in source
    assert "RowLayout" not in source
    assert source.count("Todo.list.filter(") == 1
    assert "readonly property var pendingTodos:" in source


def test_settings_window_relies_on_fixed_size_instead_of_transient_rules():
    source = Path("modules/ii/settings/Settings.qml").read_text()
    assert 'title: Translation.tr("Settings")' in source
    assert "minimumSize.width: root.windowWidth" in source
    assert "minimumSize.height: root.windowHeight" in source
    assert "maximumSize.width: root.windowWidth" in source
    assert "maximumSize.height: root.windowHeight" in source
    assert 'Quickshell.execDetached(["hyprctl", "eval"' not in source
    assert "end4_settings_window_rule" not in source


def test_tray_grid_uses_spacing_tokens_and_lint_covers_grid_gaps():
    tray = Path("modules/ii/bar/SysTray.qml").read_text()
    lint = Path("tests/lint_spacing.py").read_text()
    assert "columnSpacing: Appearance.spacing.space75" in tray
    assert "rowSpacing: Appearance.spacing.space75" in tray
    # Grid gaps and the QQC2 axis paddings are spelled differently from plain
    # `spacing`/`padding`, so each name has to be listed explicitly or the lint
    # silently passes raw literals on those properties.
    for prop in ("rowSpacing", "columnSpacing", "horizontalPadding", "verticalPadding"):
        assert f"|{prop}" in lint, f"lint does not cover {prop}"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
