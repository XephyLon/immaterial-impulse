import QtQuick
import Quickshell
import qs.modules.imi.bar as Bar

// One BarExclusiveZoneReserver, on its own, with its zone flipped between the
// two ends of auto-hide. Driven by tests/run_bar_exclusive_zone_probe.sh under
// a nested Hyprland, which is the only place a wlr-layer-shell exclusive zone
// can be observed at all - see that script's header.
//
// Deliberately not the whole bar: what is being measured is the reserved area,
// and a real bar would put its own surface, its blur region and its content
// tree between the reader and the one number in question.
ShellRoot {
    id: root

    property bool out: false

    Bar.BarExclusiveZoneReserver {
        screen: Quickshell.screens[0]
        barNamespace: "quickshell:bar"
        edgeMargin: 5
        zone: root.out ? 40 : 0
        onAnimatedZoneChanged: console.log(`[BarZoneProbe] animated=${animatedZone.toFixed(2)}`)
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            root.out = !root.out;
            console.log(`[BarZoneProbe] zone target ${root.out ? "out" : "hidden"}`);
        }
    }
}
