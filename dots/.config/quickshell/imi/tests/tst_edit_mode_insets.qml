import QtQuick
import QtTest
import qs.modules.common
import qs.modules.imi.editMode
import "../modules/imi/dock/dock_geometry.js" as DockGeometry

// What Edit Mode subtracts from the screen before it shrinks the desktop into
// what is left: the bar's edge and the dock's.
//
// `tst_edit_mode.qml` proves the arithmetic that consumes these four numbers
// and takes them as arguments. This is the other half - that the numbers handed
// in are the ones the two panels really occupy - and it is reachable here for
// the same reason `tst_bar_geometry.qml` is: they are arithmetic between real
// `Appearance` tokens and real `Config` values, with no surface involved.
//
// The expectations are the sizes the compositor reports on the machine this was
// measured against (`hyprctl layers`: `quickshell:bar` at y=5 h=63,
// `quickshell:dock` 5120x75), rather than the expression restated - a check
// that restates the expression agrees with itself whatever the expression says.
TestCase {
    name: "EditModeInsetsTest"

    property int savedCornerStyle: 0
    property bool savedBottom: false
    property bool savedVertical: false
    property bool savedAutoHide: false
    property bool savedDockEnable: true
    property string savedDockEdge: "bottom"

    function initTestCase() {
        savedCornerStyle = Config.options.bar.cornerStyle;
        savedBottom = Config.options.bar.bottom;
        savedVertical = Config.options.bar.vertical;
        savedAutoHide = Config.options.bar.autoHide.enable;
        savedDockEnable = Config.options.dock.enable;
        savedDockEdge = Config.options.dock.edge;
    }

    function cleanupTestCase() {
        Config.options.bar.cornerStyle = savedCornerStyle;
        Config.options.bar.bottom = savedBottom;
        Config.options.bar.vertical = savedVertical;
        Config.options.bar.autoHide.enable = savedAutoHide;
        Config.options.dock.enable = savedDockEnable;
        Config.options.dock.edge = savedDockEdge;
    }

    function detached() {
        Config.options.bar.cornerStyle = 3;
        Config.options.bar.bottom = false;
        Config.options.bar.vertical = false;
        Config.options.bar.autoHide.enable = false;
    }

    function test_the_bars_surface_is_the_size_the_compositor_reports() {
        detached();
        compare(Appearance.sizes.barSurfaceHeight, 63);
        compare(Appearance.sizes.barSurfaceMargin, 5);
        compare(Appearance.sizes.barSurfaceThickness, 68);
    }

    function test_the_bar_reserves_its_body_and_its_corner_decorators_alike() {
        // The surface is 23px taller than the 40px body: `screenRounding`, for
        // the corner decorators that hang below it and take clicks there. The
        // reservation is the SURFACE, which is also the number `hyprctl layers`
        // reports, so a regression here is a number rather than an impression
        // that something moved.
        detached();
        compare(Appearance.sizes.barSurfaceHeight - Appearance.sizes.barHeight,
            Appearance.rounding.screenRounding);
    }

    function test_auto_hide_moves_the_gap_inside_the_surface_without_changing_its_reach() {
        // `barDetachInset` takes the gap off the margin and puts it inside the
        // window, so the surface reaches the same distance from the edge either
        // way - which is what makes reserving against configuration rather than
        // against the current hidden/shown state a stable number.
        detached();
        const shown = Appearance.sizes.barSurfaceThickness;
        Config.options.bar.autoHide.enable = true;
        compare(Appearance.sizes.barSurfaceThickness, shown);
        compare(Appearance.sizes.barSurfaceMargin, 0);
        Config.options.bar.autoHide.enable = false;
    }

    function test_the_dock_reserves_the_thickness_its_own_module_derives() {
        // Not a second copy of the sum: `dock_geometry.js` is where the dock's
        // thickness lives and this is the same call the dock's own window
        // makes. At the defaults it is the 75 the compositor reports.
        compare(DockGeometry.thickness(60, Appearance.sizes.elevationMargin,
            Appearance.sizes.hyprlandGapsOut), 75);
    }

    function test_the_insets_land_on_the_edges_the_two_panels_are_on() {
        detached();
        Config.options.dock.enable = true;
        Config.options.dock.edge = "bottom";
        let insets = EditModeInsets.insetsFor("DP-1");
        compare(insets.top, 68);
        compare(insets.bottom, 75);
        compare(insets.left, 0);
        compare(insets.right, 0);

        // A bottom bar over a bottom dock share an edge, so the two terms ADD
        // rather than the larger winning - the chrome has to clear both.
        Config.options.bar.bottom = true;
        insets = EditModeInsets.insetsFor("DP-1");
        compare(insets.top, 0);
        compare(insets.bottom, 68 + 75);

        // A vertical bar moves onto a side edge, where `bar.bottom` means right
        // rather than bottom.
        Config.options.bar.vertical = true;
        insets = EditModeInsets.insetsFor("DP-1");
        compare(insets.bottom, 75);
        compare(insets.right, Appearance.sizes.verticalBarSurfaceWidth);
        compare(insets.left, 0);

        Config.options.bar.vertical = false;
        Config.options.bar.bottom = false;
    }

    function test_a_dock_that_is_switched_off_reserves_nothing() {
        detached();
        Config.options.dock.enable = false;
        const insets = EditModeInsets.insetsFor("DP-1");
        compare(insets.bottom, 0);
        // ...and the bar's edge is still reserved, so this cannot pass by
        // returning zeros for everything.
        compare(insets.top, 68);
        Config.options.dock.enable = true;
    }

    function test_a_screen_the_bar_is_not_drawn_on_gets_none_of_its_inset() {
        detached();
        verify(EditModeInsets.barShownOn("DP-1"));
        Config.options.bar.screenList = ["HDMI-A-1"];
        verify(!EditModeInsets.barShownOn("DP-1"));
        verify(EditModeInsets.barShownOn("HDMI-A-1"));
        compare(EditModeInsets.insetsFor("DP-1").top, 0);
        Config.options.bar.screenList = [];
        verify(EditModeInsets.barShownOn("DP-1"));
    }

    function test_the_toolbar_reserves_the_height_a_toolbar_is() {
        // The viewport reserves a band on the background surface, where no
        // toolbar exists to measure. This is the one number both it and
        // `Toolbar.qml` read; if they ever stop agreeing the chrome lands in a
        // band that is not its size.
        compare(Appearance.sizes.toolbarHeight, 56);
    }
}
