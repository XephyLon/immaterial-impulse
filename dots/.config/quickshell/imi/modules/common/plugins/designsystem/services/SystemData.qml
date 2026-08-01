pragma Singleton
import Quickshell
import qs.services

Singleton {
    readonly property real cpuUsage: ResourceUsage.cpuUsage
    readonly property real memUsage: ResourceUsage.memoryUsedPercentage
    readonly property real swapUsage: ResourceUsage.swapUsedPercentage
    readonly property real cpuTemperature: ResourceUsage.cpuTemp
    readonly property real networkRxRate: 0
    readonly property real networkTxRate: 0
    readonly property real diskReadRate: 0
    readonly property real diskWriteRate: 0
    readonly property var diskStats: [{
        mount: "/",
        usage: ResourceUsage.diskUsedPercentage,
        total: ResourceUsage.diskTotal,
        used: ResourceUsage.diskUsed
    }]
}
