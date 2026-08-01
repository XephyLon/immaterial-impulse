import QtQuick
import QtTest
import qs.services

TestCase {
    name: "AudioTest"

    function test_friendlyDeviceName() {
        var audio = Audio
        verify(audio !== null)

        // Case 1: Node has description -> should return description
        var node1 = {
            description: "My Cool Headset",
            nickname: "headset-nick",
            name: "alsa_output.pci-0000_00_1f.3.analog-stereo"
        }
        compare(audio.friendlyDeviceName(node1), "My Cool Headset")

        // Case 2: Node has no description, but has nickname -> should return nickname
        var node2 = {
            description: "",
            nickname: "headset-nick",
            name: "alsa_output.pci-0000_00_1f.3.analog-stereo"
        }
        compare(audio.friendlyDeviceName(node2), "headset-nick")

        // Case 3: Node has neither description nor nickname -> should return "Unknown"
        var node3 = {
            description: "",
            nickname: "",
            name: "alsa_output.pci-0000_00_1f.3.analog-stereo"
        }
        compare(audio.friendlyDeviceName(node3), "Unknown")
    }

    function test_appNodeDisplayName() {
        var audio = Audio

        // Case 1: has application.name property -> should return it
        var node1 = {
            properties: {
                "application.name": "Firefox"
            },
            description: "Firefox Web Browser",
            name: "firefox-stream"
        }
        compare(audio.appNodeDisplayName(node1), "Firefox")

        // Case 2: has no application.name, but has description -> should return description
        var node2 = {
            properties: {},
            description: "Firefox Web Browser",
            name: "firefox-stream"
        }
        compare(audio.appNodeDisplayName(node2), "Firefox Web Browser")

        // Case 3: has neither application.name nor description, but has name -> should return name
        var node3 = {
            properties: {},
            description: "",
            name: "firefox-stream"
        }
        compare(audio.appNodeDisplayName(node3), "firefox-stream")
    }
}
