import QtQuick
import QtTest
import testservices

// Behavioral tests for the parsing logic of services/MediaCapture.qml, exercised
// through the logic-only `MediaCapture` double in tests/imports/testservices.
// These pin the pactl source-output parsing (running vs corked, monitor/visualizer
// filtering, real-client filtering, app-name extraction) and the camera PID/comm
// parsing (integer validation is the command-injection guard before `ps`).
TestCase {
    name: "MediaCaptureTest"

    function init() {
        MediaCapture.micActive = false;
        MediaCapture.micApps = [];
        MediaCapture.cameraActive = false;
        MediaCapture.cameraApps = [];
    }

    // --- Mic (pactl -f json list source-outputs) ---

    function test_empty_output_is_inactive() {
        compare(MediaCapture.parseSourceOutputs("").active, false);
        compare(MediaCapture.parseSourceOutputs("   ").active, false);
        compare(MediaCapture.parseSourceOutputs(null).active, false);
    }

    function test_electron_stream_uses_process_binary() {
        // Vesktop reports application.name="Chromium"; the binary is the identity.
        var json = JSON.stringify([{
            corked: false, client: 99,
            properties: { "application.name": "Chromium", "application.process.binary": "vesktop", "application.process.id": "16116", "media.class": "Stream/Input/Audio" }
        }]);
        var r = MediaCapture.parseSourceOutputs(json);
        compare(r.active, true);
        compare(r.apps[0], "Vesktop");
    }

    function test_specific_app_name_wins_over_binary() {
        var json = JSON.stringify([{
            corked: false, client: 12,
            properties: { "application.name": "OBS Studio", "application.process.binary": "obs", "application.process.id": "42", "media.class": "Stream/Input/Audio" }
        }]);
        compare(MediaCapture.parseSourceOutputs(json).apps[0], "OBS Studio");
    }

    function test_json_running_client_stream_is_recording() {
        var json = JSON.stringify([{
            index: 1, client: "4363", corked: false,
            properties: { "application.name": "Chromium input", "application.process.id": "310258", "media.class": "Stream/Input/Audio" }
        }]);
        var r = MediaCapture.parseSourceOutputs(json);
        compare(r.active, true);
        compare(r.apps.length, 1);
        compare(r.apps[0], "Chromium input");
    }

    function test_json_corked_stream_is_ignored() {
        var json = JSON.stringify([{
            index: 1, client: "4363", corked: true,
            properties: { "application.name": "Chromium input", "application.process.id": "1" }
        }]);
        compare(MediaCapture.parseSourceOutputs(json).active, false);
    }

    function test_json_sink_monitor_visualizer_is_ignored() {
        // cava captures the sink monitor - must not count as mic recording.
        var json = JSON.stringify([{
            index: 1, client: null, corked: false,
            properties: { "media.name": "cava", "node.name": "cava", "stream.capture.sink": "true" }
        }]);
        compare(MediaCapture.parseSourceOutputs(json).active, false);
    }

    function test_json_filter_chain_virtual_node_is_ignored() {
        // Filter-chain / EQ node: no client, no process - not an app recording.
        var json = JSON.stringify([{
            index: 1, client: null, corked: false,
            properties: { "media.name": "Sonar Micro EQ input", "node.virtual": "true" }
        }]);
        compare(MediaCapture.parseSourceOutputs(json).active, false);
    }

    function test_json_mixed_real_sample_yields_only_recording_app() {
        var json = JSON.stringify([
            { index: 53, client: null, corked: true, properties: { "media.name": "Sonar Micro EQ input", "node.virtual": "true" } },
            { index: 308638, client: "4363", corked: false, properties: { "application.name": "Chromium input", "application.process.id": "310258" } },
            { index: 332198, client: null, corked: false, properties: { "media.name": "cava", "stream.capture.sink": "true" } }
        ]);
        var r = MediaCapture.parseSourceOutputs(json);
        compare(r.active, true);
        compare(r.apps.length, 1);
        compare(r.apps[0], "Chromium input");
    }

    function test_json_dedupes_app_names() {
        var json = JSON.stringify([
            { index: 1, client: "1", corked: false, properties: { "application.name": "OBS" } },
            { index: 2, client: "2", corked: false, properties: { "application.name": "OBS" } }
        ]);
        var r = MediaCapture.parseSourceOutputs(json);
        compare(r.active, true);
        compare(r.apps.length, 1);
    }

    function test_json_injection_metacharacters_survive_verbatim() {
        var evil = "Rec; rm -rf $HOME `whoami`";
        var json = JSON.stringify([{ index: 1, client: "1", corked: false, properties: { "application.name": evil } }]);
        var r = MediaCapture.parseSourceOutputs(json);
        compare(r.apps[0], evil);
    }

    function test_text_fallback_parses_running_client_block() {
        var text = [
            "Source Output #308638",
            "\tCorked: no",
            "\tClient: 4363",
            "\tProperties:",
            "\t\tapplication.name = \"Chromium input\"",
            "\t\tapplication.process.id = \"310258\"",
            "Source Output #332198",
            "\tCorked: no",
            "\tClient: n/a",
            "\tProperties:",
            "\t\tmedia.name = \"cava\"",
            "\t\tstream.capture.sink = \"true\""
        ].join("\n");
        var r = MediaCapture.parseSourceOutputs(text);
        compare(r.active, true);
        compare(r.apps.length, 1);
        compare(r.apps[0], "Chromium input");
    }

    // --- Camera (fuser PIDs -> ps comm) ---

    function test_parse_pids_extracts_unique_integers() {
        compare(MediaCapture.parsePids("").length, 0);
        var pids = MediaCapture.parsePids(" 1234  5678\n1234 ");
        compare(pids.length, 2);
        compare(pids[0], "1234");
        compare(pids[1], "5678");
    }

    function test_parse_pids_rejects_non_integer_tokens() {
        // Injection guard: only bare integers survive to become `ps` argv.
        var pids = MediaCapture.parsePids("1234 ;rm -rf $HOME abc 5678");
        compare(pids.length, 2);
        compare(pids[0], "1234");
        compare(pids[1], "5678");
    }

    function test_parse_comm_trims_and_dedupes() {
        var names = MediaCapture.parseComm("firefox\nfirefox\n zoom \n\n");
        compare(names.length, 2);
        compare(names[0], "firefox");
        compare(names[1], "zoom");
    }

    // --- Per-stream detail, which the privacy panel acts on ---

    function test_streams_carry_the_ids_an_action_needs() {
        // index addresses the pactl mute; object.id addresses the PipeWire node
        // a force-stop destroys. They are different numbers for the same stream.
        var json = JSON.stringify([{
            index: 262920, corked: false, mute: false, client: 3,
            properties: {
                "application.name": "Chromium",
                "application.process.binary": "vesktop",
                "application.process.id": "16116",
                "object.id": "282",
                "media.class": "Stream/Input/Audio"
            }
        }]);
        var streams = MediaCapture.parseSourceOutputs(json).streams;
        compare(streams.length, 1);
        compare(streams[0].name, "Vesktop");
        compare(streams[0].index, 262920);
        compare(streams[0].nodeId, "282");
        compare(streams[0].pid, "16116");
        compare(streams[0].muted, false);
    }

    function test_a_muted_stream_still_counts_as_recording() {
        // A muted stream is still an open microphone from the app's side: the
        // app holds the device and can unmute itself. The dot stays on, and the
        // row shows the mute so it can be undone.
        var json = JSON.stringify([{
            index: 7, corked: false, mute: true, client: 1,
            properties: { "application.name": "Zoom", "application.process.id": "9", "media.class": "Stream/Input/Audio" }
        }]);
        var r = MediaCapture.parseSourceOutputs(json);
        compare(r.active, true);
        compare(r.streams[0].muted, true);
    }

    function test_filtered_streams_do_not_reach_the_panel() {
        // Whatever is not shown as an app must not be actionable as one either.
        var json = JSON.stringify([
            { index: 1, corked: true, properties: { "application.name": "Corked", "application.process.id": "1" } },
            { index: 2, corked: false, properties: { "application.name": "Cava", "application.process.id": "2", "stream.capture.sink": "true" } }
        ]);
        compare(MediaCapture.parseSourceOutputs(json).streams, []);
    }
}
