import QtQuick
import QtQuick.Layouts

// A local stub of the sub-page host that W5a owns
// (modules/imi/sidebarLeft/phone/PhoneSubPage.qml, spec §W5). It does not
// exist in this worktree, and it must NOT be written under modules/ from
// here: two files of that name would be exactly the dead-copy hazard
// lint_no_stale_widget_canvas.py exists to fail on, one branch behind the
// other and the richer-looking of the two.
//
// What it pins is the interface the four pages in this directory are written
// against, so a real component that arrives with a different shape reddens
// tests/test_phone_tab_surface_contract.py rather than laying the pages out
// wrong on a live shell:
//
//   - `property string title` - the page names itself, the host draws the
//     title bar.
//   - `signal back()` - the host draws the back button and raises this; the
//     tab pops the overlay.
//   - a default CONTENT SLOT that is a ColumnLayout, so a page's children
//     state their size with `Layout.fillWidth` / `Layout.fillHeight` (the
//     shape ContentPage and ContentSection already use). A page anchoring to
//     its parent instead would log "Detected anchors on an item that is
//     managed by a layout" and size wrong.
Item {
    id: root

    property string title: ""
    signal back

    default property alias contentData: contentColumn.data

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
    }
}
