import QtQuick
import Quickshell

import qs.modules.common

LazyLoader {
    property bool extraCondition: true
    // activeAsync, not active: `active` instantiates synchronously, and with
    // ~28 of these firing on the same Config.ready flip, boot paid for every
    // panel - lock screen, cheatsheet, session screen - before the first
    // frame of the bar. activeAsync activates the same panels but builds
    // them incrementally between frames; the ones nobody has opened yet stop
    // gating the ones on screen.
    activeAsync: Config.ready && extraCondition
}
