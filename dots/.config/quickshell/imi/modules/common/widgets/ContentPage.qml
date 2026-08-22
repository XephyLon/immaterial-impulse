import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: 90
    property string currentSection: ""
    property var availableSections: []

    function navigationSections(item) {
        let sections = []
        for (let index = 0; index < item.children.length; index++) {
            const child = item.children[index]
            if (child.settingsNavigationSection === true)
                sections.push(child)
            else if (child.children && child.children.length > 0)
                sections = sections.concat(navigationSections(child))
        }
        return sections
    }

    function updateCurrentSection() {
        let firstSection = ""
        let visibleSection = ""
        let closestY = -Infinity
        const markerY = root.contentY + Appearance.spacing.space600

        const sections = navigationSections(contentColumn)
        const nextAvailableSections = []
        for (let index = 0; index < sections.length; index++) {
            const child = sections[index]
            if (child.title.length === 0 || !child.visible)
                continue
            nextAvailableSections.push(child.title)
            if (firstSection.length === 0)
                firstSection = child.title
            const position = child.mapToItem(contentColumn, 0, 0).y
            if (position <= markerY && position > closestY) {
                closestY = position
                visibleSection = child.title
            }
        }

        const nextSection = visibleSection || firstSection
        if (JSON.stringify(nextAvailableSections) !== JSON.stringify(root.availableSections))
            root.availableSections = nextAvailableSections
        if (nextSection !== root.currentSection)
            root.currentSection = nextSection
    }

    // Named contentData rather than data: aliasing 'data' shadows Item's own
    // member, which Qt warns about on every instantiation.
    default property alias contentData: contentColumn.data

    clip: true
    momentumScroll: true // True inertial trackpad scrolling (fling & glide)
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth
    onContentYChanged: updateCurrentSection()
    onContentHeightChanged: Qt.callLater(updateCurrentSection)
    Component.onCompleted: {
        Qt.callLater(updateCurrentSection);
        sectionEntrance.run(root.visible);
    }

    // A page's sections arrive in sequence rather than in one frame. The
    // container here is the page itself, which the settings window already
    // cross-fades over `elementMoveFast` - the lead-in is three steps of the
    // shell's own stagger, so the first section starts while that fade is most
    // of the way through rather than racing it from frame one.
    //
    // Ranking by VISIBLE position is what keeps a page whose sections come and
    // go honest: Services hides its wttr.in section, Bar hides half of its
    // own on a vertical bar, and a hidden section spending a slot would leave a
    // hole one step wide in the middle of the wave.
    StaggerWave {
        id: sectionEntrance
        target: contentColumn
        step: Appearance.animation.staggerStep
        leadIn: Appearance.animation.staggerStep * 3
    }

    // `visible` is EFFECTIVE visibility, so this follows the settings window's
    // own page switch (the page Loader binds `visible: isActive`) without this
    // component having to know anything about it.
    onVisibleChanged: sectionEntrance.run(root.visible)

    Timer {
        // Base Component.onCompleted may run before a derived settings page has
        // completed its first layout. Re-scan once after that initial polish.
        interval: 100
        running: true
        repeat: false
        onTriggered: root.updateCurrentSection()
    }
    
    ColumnLayout {
        id: contentColumn
        width: root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            margins: Appearance.spacing.space250
        }
    spacing: Appearance.spacing.space400
    }

}
