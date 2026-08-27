import QtQuick
import QtTest
import qs.services

// services/DiscordVoice.qml's session-level reconnect, driven through the real
// singleton over the Quickshell.Io mocks. The bridge PROCESS already had a
// restart ladder (onExited); "unavailable" and "disconnected" arrive from a
// bridge that is alive with nothing behind it, and nothing retried those, so
// a Discord started after the shell was never picked up until a manual
// connect.
TestCase {
    name: "DiscordVoiceReconnectTest"

    function line(type, extra) {
        return JSON.stringify(Object.assign({type: type}, extra || {}))
    }

    function init() {
        DiscordVoice.handleLine(line("connected", {socket: "/run/user/1000/discord-ipc-0"}))
        verify(!DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 0)
    }

    function test_unavailable_arms_the_retry() {
        DiscordVoice.handleLine(line("unavailable", {message: "Discord is not running or RPC is unavailable"}))
        compare(DiscordVoice.status, "unavailable")
        verify(DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 1)
    }

    function test_disconnected_arms_the_retry() {
        DiscordVoice.handleLine(line("disconnected"))
        compare(DiscordVoice.status, "disconnected")
        verify(DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 1)
    }

    function test_every_failed_answer_climbs_the_ladder() {
        DiscordVoice.handleLine(line("disconnected"))
        DiscordVoice.handleLine(line("unavailable"))
        DiscordVoice.handleLine(line("unavailable"))
        compare(DiscordVoice.reconnectAttempts, 3)
        verify(DiscordVoice.reconnectPending)
    }

    function test_connected_disarms_the_retry_and_resets_the_ladder() {
        DiscordVoice.handleLine(line("unavailable"))
        DiscordVoice.handleLine(line("unavailable"))
        DiscordVoice.handleLine(line("connected", {socket: "/run/user/1000/discord-ipc-0"}))
        verify(!DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 0)
    }

    function test_authenticated_disarms_the_retry_too() {
        // The Vesktop companion backend emits no "connected" - its first word
        // is "authenticated" - so on that path this is the only answer that
        // can stop the retry.
        DiscordVoice.handleLine(line("unavailable"))
        DiscordVoice.handleLine(line("authenticated", {user: {id: "1"}}))
        verify(!DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 0)
    }

    function test_a_manual_connect_disarms_the_retry_and_resets_the_ladder() {
        DiscordVoice.handleLine(line("unavailable"))
        DiscordVoice.handleLine(line("unavailable"))
        DiscordVoice.connect()
        verify(!DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 0)
    }

    function test_a_fired_retry_stands_down_until_the_bridge_answers_again() {
        // One shot, not a repeating timer: the retry is re-armed by the
        // bridge's next "unavailable", one rung further up the ladder.
        DiscordVoice.handleLine(line("unavailable"))
        wait(DiscordVoice.backoffDelay(1) + 100)
        verify(!DiscordVoice.reconnectPending)
        compare(DiscordVoice.reconnectAttempts, 1)
        DiscordVoice.handleLine(line("unavailable"))
        compare(DiscordVoice.reconnectAttempts, 2)
    }

    function test_the_ladder_doubles_from_one_second_to_a_thirty_second_cap() {
        compare(DiscordVoice.backoffDelay(1), 1000)
        compare(DiscordVoice.backoffDelay(2), 2000)
        compare(DiscordVoice.backoffDelay(3), 4000)
        compare(DiscordVoice.backoffDelay(5), 16000)
        compare(DiscordVoice.backoffDelay(6), 30000)
        compare(DiscordVoice.backoffDelay(40), 30000)
    }
}
