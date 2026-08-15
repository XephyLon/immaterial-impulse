pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: root
    signal clicked(event: var)
    property alias iconText: fabWidget.iconText
    property alias baseSize: fabWidget.baseSize
    // The pairing is tertiary by default, which is what every existing caller
    // wants. A destructive pair - stop a recording - needs the error role
    // instead, and recolouring is the only difference, so it is four aliases
    // rather than a second component that would drift from this one.
    property alias colBackground: fabWidget.colBackground
    property alias colBackgroundHover: fabWidget.colBackgroundHover
    property alias colRipple: fabWidget.colRipple
    property alias colOnBackground: fabWidget.colOnBackground
    default property alias fabData: fabWidget.data
    property bool enableShadow: true

    implicitWidth: fabWidget.implicitWidth
    implicitHeight: fabWidget.implicitHeight

    StyledRectangularShadow {
        visible: root.enableShadow
        target: fabWidget
        radius: fabWidget.buttonRadius
    }

    FloatingActionButton {
        id: fabWidget
        onClicked: e => root.clicked(e)
        baseSize: 48
        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer
    }
}