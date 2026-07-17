pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, CPU and Disk usage.
 */
Singleton {
    id: root
    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    property real cpuTemp: 0

    property real diskTotal: 1
    property real diskUsed: 0
    property real diskFree: 0
    property real diskUsedPercentage: diskTotal > 0 ? diskUsed / diskTotal : 0
    property list<real> diskUsageHistory: []
    property string maxAvailableDiskString: kbToGbString(diskTotal)

    property real gpuTemp: 0
    property real gpuUsage: 0
    property real vramTotal: 1
    property real vramUsed: 0
    property real vramUsedPercentage: vramTotal > 0 ? vramUsed / vramTotal : 0
    property list<real> gpuUsageHistory: []
    property list<real> vramUsageHistory: []
    property string maxAvailableVramString: kbToGbString(vramTotal)

    Process {
        id: tempProc
        command: ["bash", "-c", "sensors 2>/dev/null | grep -E 'Package id 0|Tctl|Tdie' | grep -oP '\\+\\K[0-9.]+(?=°C)' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.cpuTemp = parseFloat(text.trim())
            }
        }
    }

    Process {
        id: diskProc
        command: ["bash", "-c", "df -k / | awk 'NR==2{print $2,$3,$4}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parseDf(text)
                if (parsed) {
                    root.diskTotal = parsed.diskTotal
                    root.diskUsed  = parsed.diskUsed
                    root.diskFree  = parsed.diskFree
                }
            }
        }
    }

    Process {
        id: gpuProc
        command: ["bash", "-c", "nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parseNvidiaSmi(text)
                if (parsed) {
                    root.gpuTemp   = parsed.gpuTemp
                    root.gpuUsage  = parsed.gpuUsage
                    root.vramUsed  = parsed.vramUsed
                    root.vramTotal = parsed.vramTotal
                }
            }
        }
    }

    Timer {
        interval: Config?.options.resources.updateInterval ?? 3000
        running: true
        repeat: true
        onTriggered: {
            tempProc.running = false
            tempProc.running = true
            diskProc.running = false
            diskProc.running = true
            gpuProc.running = false
            gpuProc.running = true
        }
    }

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function parseMeminfo(text) {
        return {
            memoryTotal: Number(text.match(/MemTotal: *(\d+)/)?.[1] ?? 1),
            memoryFree:  Number(text.match(/MemAvailable: *(\d+)/)?.[1] ?? 0),
            swapTotal:   Number(text.match(/SwapTotal: *(\d+)/)?.[1] ?? 1),
            swapFree:    Number(text.match(/SwapFree: *(\d+)/)?.[1] ?? 0)
        };
    }

    function parseDf(text) {
        const parts = text.trim().split(/\s+/).map(Number)
        if (parts.length >= 3 && !parts.some(isNaN)) {
            return {
                diskTotal: parts[0],
                diskUsed:  parts[1],
                diskFree:  parts[2]
            };
        }
        return null;
    }

    function parseNvidiaSmi(text) {
        const parts = text.trim().split(",").map(s => parseFloat(s.trim()))
        if (parts.length >= 4 && !parts.some(isNaN)) {
            return {
                gpuTemp:   parts[0],
                gpuUsage:  parts[1] / 100,
                vramUsed:  parts[2] * 1024, // MiB -> KB, to match /proc/meminfo units
                vramTotal: parts[3] * 1024
            };
        }
        return null;
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) memoryUsageHistory.shift()
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) swapUsageHistory.shift()
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) cpuUsageHistory.shift()
    }
    function updateDiskUsageHistory() {
        diskUsageHistory = [...diskUsageHistory, diskUsedPercentage]
        if (diskUsageHistory.length > historyLength) diskUsageHistory.shift()
    }
    function updateGpuUsageHistory() {
        gpuUsageHistory = [...gpuUsageHistory, gpuUsage]
        if (gpuUsageHistory.length > historyLength) gpuUsageHistory.shift()
    }
    function updateVramUsageHistory() {
        vramUsageHistory = [...vramUsageHistory, vramUsedPercentage]
        if (vramUsageHistory.length > historyLength) vramUsageHistory.shift()
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
        updateDiskUsageHistory()
        updateGpuUsageHistory()
        updateVramUsageHistory()
    }

    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            fileMeminfo.reload()
            fileStat.reload()

            const textMeminfo = fileMeminfo.text()
            const parsed = root.parseMeminfo(textMeminfo)
            memoryTotal = parsed.memoryTotal
            memoryFree  = parsed.memoryFree
            swapTotal   = parsed.swapTotal
            swapFree    = parsed.swapFree

            const textStat = fileStat.text()
            const cpuLine  = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle  = stats[3]
                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff  = idle  - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }
                previousCpuStats = { total, idle }
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat;    path: "/proc/stat" }

    Process {
        id: findCpuMaxFreqProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
