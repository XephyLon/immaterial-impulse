import QtQuick

// A surface's claim on an undebounced config write.
//
// `Config` debounces `writeAdapter()` and the reload that its own write
// provokes (see the comment on `readWriteDelay` there). A surface that wants
// its writes flushed on the next turn instead - because it is about to quit,
// or because the user is sitting in it making one deliberate change at a time
// - declares one of these and binds `active` to the condition under which that
// is really true. `Config.readWriteDelay` is resolved from the live claims.
//
// It is a component rather than a `Config.readWriteDelay = 0` line at the call
// site for the reason CavaRef is one, plus a sharper one. An assignment has no
// release path at all: `SettingsContent.qml` carried exactly that assignment,
// never restored it, and left the whole shell's config writes undebounced from
// startup for the rest of the session. "Restore the previous value" is not the
// repair - a saved value is a second thing to keep in sync, it is wrong the
// moment two surfaces want the delay at once, and it still has to be put back
// by somebody. A claim states a need and its release IS its own lifetime.
//
// `active` has no default on purpose. The defect above was a claim whose
// condition was "the surface exists" written where the real condition was "the
// window is on screen", and the settings host exists from `Config.ready`
// onward. Stating the condition does not force any particular answer; it
// forces the author to have one. It is `required`, so a bare
// `ConfigWriteDelayRef {}` is a compile failure - and
// tests/lint_config_write_delay_claims.py refuses one as well, because a
// widget that fails to compile leaves this repo's suite fully green and only a
// live load surfaces it.
QtObject {
    id: root

    required property bool active
    property bool held: false

    function sync() {
        if (root.active === root.held)
            return;
        Config.immediateWriteClaims += root.active ? 1 : -1;
        root.held = root.active;
    }

    onActiveChanged: root.sync()
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (!root.held)
            return;
        Config.immediateWriteClaims--;
        root.held = false;
    }
}
