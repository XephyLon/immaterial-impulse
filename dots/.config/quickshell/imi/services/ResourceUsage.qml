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

    // GPU vendor for polling: "nvidia" (nvidia-smi), "amd"/"intel" (hwmon/sysfs),
    // or "" while detection is pending or no supported GPU was found.
    property string gpuVendor: ""

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

    // Pick a GPU polling backend once: prefer NVIDIA if nvidia-smi is present,
    // otherwise fall back to amdgpu (gpu_busy_percent) or, failing that, any GPU
    // exposing an hwmon temperature (e.g. Intel iGPUs).
    Process {
        id: gpuDetectProc
        running: true
        command: ["bash", "-c", "if command -v nvidia-smi >/dev/null 2>&1; then echo nvidia; elif ls /sys/class/drm/card*/device/gpu_busy_percent >/dev/null 2>&1; then echo amd; elif ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input >/dev/null 2>&1; then echo intel; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.gpuVendor = text.trim()
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

    // AMD/Intel fallback via Linux hwmon/sysfs. Emits a single line:
    //   "<busy%> <temp_millideg> <vram_used_bytes> <vram_total_bytes>"
    // busy comes from amdgpu's gpu_busy_percent (absent on Intel iGPUs, where it
    // reports 0/unavailable); temperature from the GPU hwmon temp1_input; VRAM
    // from mem_info_vram_* when the driver exposes it (amdgpu). Paths are static
    // globs, so this stays a fixed command with no untrusted interpolation.
    Process {
        id: gpuFallbackProc
        command: ["bash", "-c", "for d in /sys/class/drm/card*/device; do [ -d \"$d\" ] || continue; busy=$(cat \"$d/gpu_busy_percent\" 2>/dev/null); temp=$(cat \"$d\"/hwmon/hwmon*/temp1_input 2>/dev/null | head -1); vu=$(cat \"$d/mem_info_vram_used\" 2>/dev/null); vt=$(cat \"$d/mem_info_vram_total\" 2>/dev/null); if [ -n \"$busy\" ] || [ -n \"$temp\" ]; then echo \"${busy:-0} ${temp:-0} ${vu:-0} ${vt:-0}\"; break; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = root.parseAmdGpu(text)
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
            if (root.gpuVendor === "nvidia") {
                gpuProc.running = false
                gpuProc.running = true
            } else if (root.gpuVendor === "amd" || root.gpuVendor === "intel") {
                gpuFallbackProc.running = false
                gpuFallbackProc.running = true
            }
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

    // Parses the AMD/Intel sysfs fallback line:
    //   "<busy%> <temp_millideg> <vram_used_bytes> <vram_total_bytes>"
    // Temperature is millidegrees -> °C; VRAM is bytes -> KB (to match
    // /proc/meminfo units). On Intel iGPUs gpu_busy_percent is unavailable and
    // arrives as 0, so usage stays 0 while temperature still works.
    function parseAmdGpu(text) {
        const parts = text.trim().split(/\s+/).map(s => parseFloat(s))
        if (parts.length < 4 || isNaN(parts[0]) || isNaN(parts[1])) {
            return null;
        }
        const vramUsed  = isNaN(parts[2]) ? 0 : parts[2]
        const vramTotal = (isNaN(parts[3]) || parts[3] <= 0) ? 1024 : parts[3]
        return {
            gpuTemp:   parts[1] / 1000,
            gpuUsage:  parts[0] / 100,
            vramUsed:  vramUsed / 1024,
            vramTotal: vramTotal / 1024
        };
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
