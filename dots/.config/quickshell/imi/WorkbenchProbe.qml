import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.imi.cheatsheet

ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 1800
        implicitHeight: 1000
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
        CheatsheetComponents { id: comp; anchors.fill: parent }

        function typeName(o) { return `${o}`.split("(")[0].replace(/_QMLTYPE.*/, ""); }
        function walk(o, fn) { fn(o); for (const c of o.children ?? []) walk(c, fn); }
        function scroller() {
            let found = null;
            walk(comp, o => { if (!found && typeName(o) === "ScrollView") found = o; });
            return found;
        }

        IpcHandler {
            target: "probe"
            function dumpTiles(): string {
                const out = [];
                win.walk(comp, o => {
                    if (win.typeName(o) !== "ComponentStage" || !o.visible) return;
                    const p = o.mapToItem(null, 0, 0);
                    // only the gallery's stages: they sit inside a tile with a name label
                    if (o.width < 10 || o.height < 10) return;
                    out.push(`${o.typeName} ${p.x.toFixed(0)} ${p.y.toFixed(0)} ${o.width.toFixed(0)} ${o.height.toFixed(0)} ${o.control ? 1 : 0} ${o.inert ? 1 : 0}`);
                });
                return out.join("\n");
            }
            function scroll(y: real): real {
                const s = win.scroller();
                if (!s) return -1;
                s.contentItem.contentY = Math.max(0, Math.min(y, s.contentHeight - s.height));
                return s.contentItem.contentY;
            }
            function scrollMax(): real { const s = win.scroller(); return s ? s.contentHeight - s.height : -1; }
            function pick(name: string): string {
                const e = comp.allEntries.find(e => comp.nameOf(e) === name);
                if (!e) return "no such entry";
                comp.show(e);
                return e.type;
            }
            function dumpKnobs(): string {
                const out = [];
                win.walk(comp, o => {
                    if (!/RowLayout/.test(win.typeName(o)) || !o.modelData || !o.modelData.kind) return;
                    for (const c of o.children) {
                        if (!c.visible || c.width < 5) continue;
                        const t = win.typeName(c);
                        if (!/TextField|SpinBox|Switch/.test(t)) continue;
                        // the number knob is a ConfigSpinBox ROW; the input is the StyledSpinBox inside it
                        let target = c;
                        if (/ConfigSpinBox/.test(t)) win.walk(c, x => { if (/StyledSpinBox/.test(win.typeName(x))) target = x; });
                        const p = target.mapToItem(null, 0, 0);
                        out.push(`${o.modelData.name} ${o.modelData.kind} ${p.x.toFixed(0)} ${p.y.toFixed(0)} ${target.width.toFixed(0)} ${target.height.toFixed(0)}`);
                    }
                });
                return out.join("\n");
            }
            function tileInfo(name: string): string {
                let out = "none";
                win.walk(comp, o => {
                    if (win.typeName(o) !== "ComponentStage" || !o.inert || o.typeName !== name || !o.visible || o.width < 10) return;
                    const c = o.control;
                    out = `stage ${o.width.toFixed(0)}x${o.height.toFixed(0)} fit ${o.fitScale.toFixed(3)} control impl ${c?.implicitWidth.toFixed(0)}x${c?.implicitHeight.toFixed(0)} size ${c?.width.toFixed(0)}x${c?.height.toFixed(0)} at ${o.mapToItem(null,0,0).x.toFixed(0)},${o.mapToItem(null,0,0).y.toFixed(0)} ctrl ${c?.mapToItem(null,0,0).x.toFixed(0)},${c?.mapToItem(null,0,0).y.toFixed(0)}`;
                });
                return out;
            }
            function treeInfo(name: string): string {
                let out = [];
                win.walk(comp, o => {
                    if (win.typeName(o) !== "ComponentStage" || !o.inert || o.typeName !== name || !o.visible || o.width < 10) return;
                    const c = o.control;
                    function rec(item, depth) {
                        if (depth > 4) return;
                        for (const k of item.children ?? []) {
                            if (k.width === undefined || !k.visible) continue;
                            const p = k.mapToItem(c, 0, 0);
                            out.push("  ".repeat(depth) + win.typeName(k).replace("QQuick", "") + ` x ${p.x.toFixed(0)} w ${k.width.toFixed(0)} iw ${k.implicitWidth.toFixed(0)}` + (k.text !== undefined ? ` "${k.text}"` : ""));
                            rec(k, depth + 1);
                        }
                    }
                    out.push(`control w ${c.width.toFixed(0)} iw ${c.implicitWidth.toFixed(0)}`);
                    rec(c, 1);
                });
                return out.join("\n");
            }
            function detailState(): string {
                let st = null;
                win.walk(comp, o => { if (win.typeName(o) === "ComponentStage" && !o.inert) st = o; });
                if (!st) return "nostage";
                const p = st.mapToItem(null, 0, 0);
                const m = st.measurements;
                return `${st.control ? 1 : 0}|${st.failure}|${m ? m.width.toFixed(0) + "x" + m.height.toFixed(0) : "-"}|${p.x.toFixed(0)} ${p.y.toFixed(0)} ${st.width.toFixed(0)} ${st.height.toFixed(0)}|${st.control ? st.control.enabled : "-"}|${st.control && st.control.toggled !== undefined ? st.control.toggled : "-"}`;
            }
        }
    }
}
