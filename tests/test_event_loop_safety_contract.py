from pathlib import Path


def test_removed_notification_timer_is_a_noop():
    source = Path("services/Notifications.qml").read_text()
    guard = source.index("if (!notifObject)")
    dereference = source.index("if (notifObject.isTransient)")
    assert guard < dereference
    assert "destroy();\n                return;" in source[guard:dereference]


def test_system_icon_loader_has_no_item_size_feedback_loop():
    source = Path("modules/ii/bar/SystemIcons.qml").read_text()
    assert "width: active ? item?.implicitWidth" not in source
    assert "height: active ? item?.implicitHeight" not in source
    assert "implicitWidth: active ? item?.implicitWidth" not in source
    assert "implicitHeight: active ? item?.implicitHeight" not in source


def test_system_icons_use_stable_implicit_layout_geometry():
    source = Path("modules/ii/bar/SystemIcons.qml").read_text()
    assert "GridLayout {\n        id: flow" in source
    assert "columns: root.vertical ? 1 : -1" in source
    assert "Flow {\n        id: flow" not in source


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
    assert "active: true" in source
    assert "visible: root.popupVisible" in source
    assert "readonly property bool targetHovered: hoverTarget?.containsMouse ?? false" in source
    assert "root.hoverTarget.QsWindow.mapFromItem(" in source
    assert "root.QsWindow?.mapFromItem(" not in source
    assert "readonly property real centerOffsetX" not in source
    assert "Component.onCompleted: initialPositionTimer.start()" in source
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
