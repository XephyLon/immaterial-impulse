import QtTest
import "../modules/common/plugins/InstalledManifestState.js" as InstalledManifestState

TestCase {
    name: "InstalledManifestStateTest"

    readonly property string firstPath: "/plugins/first/manifest.json"
    readonly property string secondPath: "/plugins/second/manifest.json"
    readonly property string newPath: "/plugins/new/manifest.json"

    function test_removedManifestIsDroppedWhileSurvivorIsKept() {
        const first = { id: "first" }
        const second = { id: "second" }
        const current = {}
        current[firstPath] = first
        current[secondPath] = second

        const result = InstalledManifestState.reconcile([secondPath], current)

        compare(Object.keys(result), [secondPath])
        compare(result[secondPath], second)
        compare(Object.keys(current).length, 2)
    }

    function test_emptyScanClearsTheVisualManifestCache() {
        const current = {}
        current[firstPath] = { id: "first" }

        const result = InstalledManifestState.reconcile([], current)

        compare(Object.keys(result), [])
    }

    function test_newPathWaitsForItsFileViewWithoutLosingSurvivors() {
        const first = { id: "first" }
        const current = {}
        current[firstPath] = first

        const result = InstalledManifestState.reconcile([firstPath, newPath], current)

        compare(Object.keys(result), [firstPath])
        compare(result[firstPath], first)
        verify(result[newPath] === undefined)
    }
}
