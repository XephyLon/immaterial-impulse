pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.modules.common
import qs.services

/**
 * Key-press feedback for the typing test.
 *
 * The samples are Monkeytype's own, vendored into the shell assets (see
 * scripts/typing/sync_monkeytype_sounds.py). They are played in-process
 * rather than through the XDG event player: this is per-keystroke feedback,
 * so it must not be rate limited, must not go through the system sound
 * theme, and must be able to overlap itself at 100+ WPM.
 *
 * In-process means MediaPlayer + AudioOutput, NOT SoundEffect. Measured on
 * Qt 6.11 against a real PipeWire session with the default sink's monitor
 * recorded: a SoundEffect - bare or with its audioDevice named - reports
 * Ready and `playing` and puts nothing on the sink (its stream stays corked
 * and muted, or never opens), while a MediaPlayer on the same file, same
 * device, peaks the monitor at 7.8k. The pool is MediaPlayers, each naming
 * the default output, restarted per keystroke.
 *
 * Nothing is instantiated until the feature is switched on — QtMultimedia
 * links its backend and starts an audio thread the moment a player exists.
 */
Item {
    id: root

    property bool soundEnabled: Config.options.cheatsheet.typingTest.sounds.enable
    property bool errorSound: Config.options.cheatsheet.typingTest.sounds.errorSound
    property real volume: Math.max(0, Math.min(100, Config.options.cheatsheet.typingTest.sounds.volume)) / 100

    readonly property var clickPack: TypingSoundPacks.clickPack(Config.options.cheatsheet.typingTest.sounds.theme)
    readonly property var errorPack: TypingSoundPacks.errorPack(Config.options.cheatsheet.typingTest.sounds.errorTheme)
    // Two players per variant so a fast typist never cuts a sample short by
    // restarting the one that is still ringing.
    readonly property int poolSize: Math.max(1, (root.clickPack?.files?.length ?? 1) * 2)
    property int _next: 0

    function playKey() {
        if (!root.soundEnabled || !poolLoader.item)
            return;
        const player = poolLoader.item.keyAt(root._next);
        root._next = (root._next + 1) % root.poolSize;
        poolLoader.item.trigger(player);
    }

    function playError() {
        if (!root.soundEnabled || !root.errorSound || !poolLoader.item)
            return;
        poolLoader.item.trigger(poolLoader.item.errorPlayer);
    }

    Loader {
        id: poolLoader
        active: root.soundEnabled && TypingSoundPacks.loaded

        sourceComponent: Item {
            readonly property alias errorPlayer: errorEffect

            // Every player names its output, bound so a change of default
            // sink follows.
            MediaDevices { id: outputs }

            function keyAt(index) {
                return keyPool.objectAt(index);
            }

            // stop() then play(): a player that has reached its end restarts
            // from the top either way, one still ringing is cut and restarted,
            // and one whose media has not loaded yet (the first beat after the
            // pool is built) plays nothing rather than queueing a late click.
            function trigger(player) {
                if (!player)
                    return;
                player.stop();
                player.play();
            }

            Instantiator {
                id: keyPool
                model: root.poolSize

                delegate: MediaPlayer {
                    required property int index
                    source: TypingSoundPacks.variantUrl(root.clickPack, index)
                    audioOutput: AudioOutput {
                        device: outputs.defaultAudioOutput
                        volume: root.volume
                    }
                }
            }

            MediaPlayer {
                id: errorEffect
                source: TypingSoundPacks.variantUrl(root.errorPack, 0)
                audioOutput: AudioOutput {
                    device: outputs.defaultAudioOutput
                    volume: root.volume
                }
            }
        }
    }
}
