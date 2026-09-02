pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.state
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.writeAdapter()
        }
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject ai: JsonObject {
                // No built-in models ship any more; empty until the
                // user's first pick from their own providers.
                property string model: ""
                property real temperature: 0.5
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
            }

            // Typing test scores. Only aggregate metrics are kept - never the
            // target text and never the keys that were actually pressed.
            property JsonObject typingTest: JsonObject {
                property list<var> recentResults: []
                property list<var> personalBests: []
                // Lifetime tallies. They outlive `recentResults`, which is
                // capped, so "tests completed" stays true after the oldest
                // results have been pruned away.
                property int testsStarted: 0
                property int testsCompleted: 0
                property real secondsTyping: 0
                // [{ d: "YYYY-MM-DD", n: tests }], one entry per active day,
                // bounded to roughly a year - enough for the activity map and
                // far smaller than keeping every result to derive it.
                property list<var> activity: []
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
            }

            property JsonObject booru: JsonObject {
                property bool allowNsfw: false
                property string provider: "yandere"
            }

            property JsonObject night: JsonObject {
                property bool temperatureActive: false
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
            }

            property JsonObject record: JsonObject {
                property bool enable: false
                // The geometry a region recording was started with, "X,Y WxH",
                // or empty for a full-screen one. Persisted beside `enable`
                // because the recording outlives the shell: record.sh owns the
                // process, so a shell restart mid-capture has to be able to
                // find its way back to the rectangle being recorded.
                property string region: ""
                // Unix seconds the current recording started, 0 when idle.
                // Written by record.sh beside `enable`, and persisted for
                // the same reason: the recording outlives the shell, and
                // the bar's elapsed timer has to survive a restart.
                property real startedAt: 0
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "volumeMixer", "resources"]
                property JsonObject crosshair: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 827
                    property real y: 441
                    property real width: 250
                    property real height: 100
                }
                property JsonObject floatingImage: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1650
                    property real y: 390
                    property real width: 0
                    property real height: 0
                }
                property JsonObject fpsLimiter: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1570
                    property real y: 615
                    property real width: 280
                    property real height: 80
                }
                property JsonObject recorder: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 80
                    property real width: 350
                    property real height: 130
                }
                property JsonObject resources: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1500
                    property real y: 770
                    property real width: 350
                    property real height: 200
                    property int tabIndex: 0
                }
                property JsonObject volumeMixer: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 280
                    property real width: 350
                    property real height: 600
                    property int tabIndex: 0
                }
                property JsonObject notes: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1400
                    property real y: 42
                    property real width: 460
                    property real height: 330
                }
                property JsonObject discordVoice: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 500
                    property real width: 380
                    property real height: 190
                }
            }

            // The Phone tab's state. The notification cache is
            // PhoneNotifications' (one JSON document keyed by device id);
            // the scrcpy/contacts workstreams add their keys beside it.
            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property list<var> laps: []
                }
            }

            property JsonObject phone: JsonObject {
                // The device the Phone tab is about, and the ones it was
                // about recently (MRU, newest first).
                property string activeDeviceId: ""
                property list<string> recentDeviceIds: []
                // The last notification sweep, so the tab is not empty
                // before the first one after a restart.
                property string cachedNotificationsJson: ""
                property JsonObject scrcpy: JsonObject {
                    property list<string> recentPackages: []
                }
                property JsonObject camera: JsonObject {
                    property string lastMode: "wifi"
                    property string lastIp: ""
                    property int lastPort: 4747
                }
                property JsonObject mic: JsonObject {
                    // The user's real default sink while it is swapped to
                    // DroidCam-Mic for scrcpy's stream to land on. Persisted
                    // so a shell restart mid-launch can put it back.
                    property string originalDefaultSink: ""
                    property string lastBackend: ""
                    property string lastMode: "wifi"
                    property string lastIp: ""
                    property int lastPort: 4748
                }
            }
        }
    }
}
