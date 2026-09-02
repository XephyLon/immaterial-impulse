import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "modules/imi/bar" as Bar

// Geometry of the popup anchor indicator against the visual it marks and the
// bar surface, for the widgets that hold a popup open on a click. Run under a
// headless compositor with isolated XDG dirs and a config copy patched to a
// bar style (the harness is in AGENT.md's entry), then:
//   quickshell ipc --pid <pid> call probe arm ; ... call probe boxes
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 600; implicitHeight: 200
        color: Appearance.colors.colLayer0
        Row {
            anchors.centerIn: parent
            spacing: 40
            Bar.DockerPlugin { id: docker }
            Bar.DiscordVoicePlugin { id: discord }
        }
    }
    function findIndicator(item) {
        if (!item) return null;
        if (item.wraps !== undefined && item.edgeItem !== undefined && item.grow !== undefined) return item;
        for (let i = 0; i < item.children.length; i++) { const r = findIndicator(item.children[i]); if (r) return r; }
        return null;
    }
    function box(item) { const r = item.mapToItem(null, 0, 0, item.width, item.height); return `${r.x.toFixed(1)},${r.y.toFixed(1)} ${r.width.toFixed(1)}x${r.height.toFixed(1)}`; }
    IpcHandler {
        target: "probe"
        function arm(): string { for (const w of [docker, discord]) { const o = findIndicator(w); if (o) o.shown = true; } return "armed"; }
        function boxes(): string {
            const out = [`style=${Config.options.bar.cornerStyle} vertical=${Config.options.bar.vertical} bottom=${Config.options.bar.bottom}`];
            for (const [name, w] of [["docker", docker], ["discord", discord]]) {
                const o = findIndicator(w);
                out.push(`${name}: root ${box(w)} | wraps ${o && o.wraps ? box(o.wraps) : "none"} | indicator ${o ? box(o) : "none"} edge=${o ? o.edge : "-"} opacity=${o ? o.opacity.toFixed(2) : "-"} onRoot=${o ? (o.parent === w) : "-"} surfaceInset=${o ? o.surfaceInset : "-"}`);
            }
            return out.join("\n");
        }
    }
}
