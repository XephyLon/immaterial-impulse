import QtQuick

/**
 * The context Edit Mode's Lockscreen tab hands to `LockSurface` - a component
 * that satisfies `LockContext`'s whole property surface and can do nothing.
 *
 * A separate component, deliberately, rather than the real context with a
 * flag: "the preview context is the real one with a flag" is how a preview
 * ends up authenticating (spec §4.3). The real `LockContext` constructs two
 * pam authentication contexts and asks the fingerprint daemon about enrolled
 * prints the moment it is built; this one is a plain `QtObject` that
 * constructs nothing, spawns nothing, and whose unlock functions have empty
 * bodies by contract - `tests/test_lock_preview_contract.py` enumerates the
 * real context's surface against this file and holds this file to its
 * negatives (which is also why this comment names none of the forbidden
 * constructs by their exact spelling: the sweep reads the whole file, so the
 * words themselves may not appear here), and a property added to
 * `LockContext` without a counterpart here reddens the suite instead of
 * reading as `undefined` on the preview.
 *
 * It also writes none of the `GlobalStates.screenLock*` flags the real
 * context maintains: those describe the actual lock session, and a preview
 * that wrote them would be a second author of the state the bar and the OSDs
 * read.
 *
 * `fingerprintsConfigured` stays false, so the preview never shows the
 * fingerprint glyph even on a machine that has prints enrolled. That is a
 * known fidelity gap, accepted: the only way to know is to ask the daemon,
 * and asking is exactly what this component exists not to do.
 */
QtObject {
    id: root

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
    }

    function tryUnlock(alsoInhibitIdle = false) {
    }

    function tryFingerUnlock() {
    }

    function stopFingerPam() {
    }
}
