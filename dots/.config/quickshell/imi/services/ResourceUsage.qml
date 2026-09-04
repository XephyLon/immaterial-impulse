pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, CPU and Disk usage.
 *
 * Polling is arranged to cost as little as possible per tick: everything that
 * the kernel exposes as a file (meminfo, stat, hwmon temperature, amdgpu
 * counters, the dGPU's runtime-PM status) is read through a FileView, and a
 * subprocess is spawned only where no file exists (nvidia-smi, df, and the
 * `sensors` fallback on machines whose CPU sensor probeProc cannot name).
 * Before this arrangement a 3s tick spawned bash+sensors+grep+grep+head,
 * bash+df+awk and a GPU probe - ~9 processes every 3 seconds for the life of
 * the shell.
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

    // Resolved once at startup by probeProc: which files answer each question
    // on this machine. Empty paths mean "no such source here".
    property var probes: ({
        cpuTempPath: "",
        gpuVendor: "",
        gpuPaths: { busy: "", temp: "", vramUsed: "", vramTotal: "" },
        nvidiaPmPath: ""
    })

    // GPU vendor for polling: "nvidia" (nvidia-smi), "amd"/"intel" (hwmon/
    // sysfs), or "" while detection is pending or no supported GPU was found.
    readonly property string gpuVendor: probes.gpuVendor

    // Resolves every pollable file path in one startup spawn: the CPU
    // temperature's hwmon input, and the GPU backend with its sysfs paths.
    // Detection order (nvidia first) is unchanged from the old per-vendor
    // probes so no machine changes which GPU it reports.
    Process {
        id: probeProc
        running: true
        command: ["bash", "-c", `
            cpu=-
            for h in /sys/class/hwmon/hwmon*; do
                name=$(cat "$h/name" 2>/dev/null)
                case "$name" in
                    coretemp)
                        for l in "$h"/temp*_label; do
                            [ -e "$l" ] || continue
                            if grep -q 'Package id 0' "$l" 2>/dev/null; then cpu="\${l%_label}_input"; break; fi
                        done
                        [ "$cpu" = - ] && [ -e "$h/temp1_input" ] && cpu="$h/temp1_input"
                        ;;
                    k10temp|zenpower)
                        [ -e "$h/temp1_input" ] && cpu="$h/temp1_input"
                        ;;
                esac
                [ "$cpu" != - ] && break
            done
            echo "cputemp $cpu"

            if command -v nvidia-smi >/dev/null 2>&1; then
                pm=-
                for d in /sys/bus/pci/devices/*; do
                    [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
                    case "$(cat "$d/class" 2>/dev/null)" in
                        0x0300*|0x0302*) pm="$d/power/runtime_status"; break;;
                    esac
                done
                echo "gpu nvidia pm=$pm"
            else
                found=
                for d in /sys/class/drm/card*/device; do
                    [ -d "$d" ] || continue
                    busy="$d/gpu_busy_percent"; [ -e "$busy" ] || busy=-
                    t=$(ls "$d"/hwmon/hwmon*/temp1_input 2>/dev/null | head -1); [ -n "$t" ] || t=-
                    if [ "$busy" != - ] || [ "$t" != - ]; then
                        vu="$d/mem_info_vram_used";  [ -e "$vu" ] || vu=-
                        vt="$d/mem_info_vram_total"; [ -e "$vt" ] || vt=-
                        vendor=amd; [ "$busy" = - ] && vendor=intel
                        echo "gpu $vendor busy=$busy temp=$t vramu=$vu vramt=$vt"
                        found=1
                        break
                    fi
                done
                [ -n "$found" ] || echo "gpu none"
            fi
        `]
        stdout: StdioCollector {
            id: probeCollector
            onStreamFinished: {
                root.probes = root.parseProbes(probeCollector.text)
            }
        }
    }

    // Fallback for machines whose CPU sensor lives on a chip probeProc does
    // not know (no coretemp/k10temp/zenpower hwmon). Only spawned while
    // probes.cpuTempPath is empty.
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

    // The kernel-file reads behind each tick. An empty path is a real "no
    // file" state for FileView: it emits nothing and reload() is a no-op, so
    // an unresolved probe costs nothing.
    FileView { id: fileMeminfo;   path: "/proc/meminfo" }
    FileView { id: fileStat;      path: "/proc/stat" }
    FileView { id: fileCpuTemp;   path: root.probes.cpuTempPath }
    FileView { id: fileNvidiaPm;  path: root.probes.nvidiaPmPath }
    FileView { id: fileGpuBusy;   path: root.probes.gpuPaths.busy }
    FileView { id: fileGpuTemp;   path: root.probes.gpuPaths.temp }
    FileView { id: fileGpuVramU;  path: root.probes.gpuPaths.vramUsed }
    FileView { id: fileGpuVramT;  path: root.probes.gpuPaths.vramTotal }

    Timer {
        interval: Config?.options.resources.updateInterval ?? 3000
        running: true
        repeat: true
        onTriggered: {
            if (root.probes.cpuTempPath !== "") {
                fileCpuTemp.reload()
                const temp = root.parseHwmonTemp(fileCpuTemp.text())
                if (temp !== null) root.cpuTemp = temp
            } else {
                tempProc.running = false
                tempProc.running = true
            }

            if (root.gpuVendor === "nvidia") {
                // An nvidia-smi run wakes a runtime-suspended dGPU, so on
                // hybrid laptops polling it every tick holds the GPU out of
                // D3 for the whole session. Poll only while it is already
                // awake; asleep means 0% busy by definition.
                fileNvidiaPm.reload()
                if (root.nvidiaShouldPoll(fileNvidiaPm.text())) {
                    gpuProc.running = false
                    gpuProc.running = true
                } else {
                    root.gpuUsage = 0
                }
            } else if (root.gpuVendor === "amd" || root.gpuVendor === "intel") {
                fileGpuBusy.reload()
                fileGpuTemp.reload()
                fileGpuVramU.reload()
                fileGpuVramT.reload()
                const parsed = root.parseAmdSysfs(
                    fileGpuBusy.text(), fileGpuTemp.text(),
                    fileGpuVramU.text(), fileGpuVramT.text())
                if (parsed) {
                    root.gpuTemp   = parsed.gpuTemp
                    root.gpuUsage  = parsed.gpuUsage
                    root.vramUsed  = parsed.vramUsed
                    root.vramTotal = parsed.vramTotal
                }
            }
        }
    }

    // Disk usage moves on the scale of minutes, and df is the one remaining
    // per-tick subprocess a fast tick would spawn - so it gets its own, much
    // slower clock instead of riding updateInterval.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            diskProc.running = false
            diskProc.running = true
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

    // The same answer assembled from the four raw sysfs files the probe
    // resolved, so the per-tick read needs no subprocess. Both primary
    // readings missing means the files went away - report that as null
    // rather than as confident zeros.
    function parseAmdSysfs(busyText, tempText, vramUsedText, vramTotalText) {
        const busy = parseFloat(String(busyText).trim())
        const temp = parseFloat(String(tempText).trim())
        if (isNaN(busy) && isNaN(temp)) return null;
        const vramUsed  = parseFloat(String(vramUsedText).trim())
        const vramTotal = parseFloat(String(vramTotalText).trim())
        return parseAmdGpu([
            isNaN(busy) ? 0 : busy,
            isNaN(temp) ? 0 : temp,
            isNaN(vramUsed) ? 0 : vramUsed,
            isNaN(vramTotal) ? 0 : vramTotal
        ].join(" "));
    }

    // hwmon temp*_input is millidegrees Celsius. Garbage or an empty read is
    // null - never a confident zero degrees (the Number(null)-is-0 trap).
    function parseHwmonTemp(text) {
        const trimmed = String(text).trim()
        if (trimmed === "") return null;
        const v = parseFloat(trimmed)
        return isNaN(v) ? null : v / 1000;
    }

    // One record per line: "cputemp <path|->" and one of
    // "gpu nvidia pm=<path|->", "gpu amd|intel busy=.. temp=.. vramu=.. vramt=..",
    // "gpu none". Unknown lines are ignored; "-" resolves to "" (no file).
    function parseProbes(text) {
        const result = {
            cpuTempPath: "",
            gpuVendor: "",
            gpuPaths: { busy: "", temp: "", vramUsed: "", vramTotal: "" },
            nvidiaPmPath: ""
        };
        for (const line of String(text).split("\n")) {
            const parts = line.trim().split(/\s+/)
            if (parts[0] === "cputemp" && parts.length >= 2) {
                result.cpuTempPath = parts[1] === "-" ? "" : parts[1]
            } else if (parts[0] === "gpu" && parts.length >= 2 && parts[1] !== "none") {
                result.gpuVendor = parts[1]
                for (const kv of parts.slice(2)) {
                    const eq = kv.indexOf("=")
                    if (eq < 1) continue;
                    const key = kv.slice(0, eq)
                    const value = kv.slice(eq + 1)
                    const path = value === "-" ? "" : value
                    if (key === "pm") result.nvidiaPmPath = path
                    else if (key === "busy") result.gpuPaths.busy = path
                    else if (key === "temp") result.gpuPaths.temp = path
                    else if (key === "vramu") result.gpuPaths.vramUsed = path
                    else if (key === "vramt") result.gpuPaths.vramTotal = path
                }
            }
        }
        return result;
    }

    // Whether an nvidia-smi poll is allowed right now, from the dGPU's
    // power/runtime_status. "suspended"/"suspending" means the poll itself
    // would power the GPU up; anything else (active, resuming, or no
    // runtime-status file at all on desktops) polls as before.
    function nvidiaShouldPoll(runtimeStatusText) {
        const status = String(runtimeStatusText).trim()
        return status !== "suspended" && status !== "suspending";
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
