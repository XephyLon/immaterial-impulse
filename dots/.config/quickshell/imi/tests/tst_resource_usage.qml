import QtQuick
import QtTest
import qs.services

TestCase {
    name: "ResourceUsageTest"

    function test_parseMeminfo() {
        var ru = ResourceUsage
        verify(ru !== null)

        var meminfoData = 
            "MemTotal:       32646272 kB\n" +
            "MemFree:         4827504 kB\n" +
            "MemAvailable:   18456208 kB\n" +
            "Buffers:          218204 kB\n" +
            "Cached:          9856208 kB\n" +
            "SwapTotal:       8388604 kB\n" +
            "SwapFree:        7954120 kB\n"

        var parsed = ru.parseMeminfo(meminfoData)
        compare(parsed.memoryTotal, 32646272)
        compare(parsed.memoryFree, 18456208) // MemAvailable is used for memoryFree
        compare(parsed.swapTotal, 8388604)
        compare(parsed.swapFree, 7954120)
    }

    function test_parseDf() {
        var ru = ResourceUsage

        // df output contains 3 parts (Total, Used, Free in KB)
        var dfData = "  245110756  12345678  232765078\n"
        var parsed = ru.parseDf(dfData)
        verify(parsed !== null)
        compare(parsed.diskTotal, 245110756)
        compare(parsed.diskUsed, 12345678)
        compare(parsed.diskFree, 232765078)

        // Invalid output
        var dfDataInvalid = "invalid output"
        var parsedInvalid = ru.parseDf(dfDataInvalid)
        verify(parsedInvalid === null)
    }

    function test_parseNvidiaSmi() {
        var ru = ResourceUsage

        // nvidia-smi format: temp, gpu_util, mem_used, mem_total
        // e.g. "55, 42, 1024, 8192"
        var gpuData = "55, 42, 1024, 8192\n"
        var parsed = ru.parseNvidiaSmi(gpuData)
        verify(parsed !== null)
        compare(parsed.gpuTemp, 55)
        compare(parsed.gpuUsage, 0.42) // 42% -> 0.42
        compare(parsed.vramUsed, 1024 * 1024) // MiB -> KB
        compare(parsed.vramTotal, 8192 * 1024)

        // Invalid output
        var gpuDataInvalid = "N/A, N/A, N/A, N/A"
        var parsedInvalid = ru.parseNvidiaSmi(gpuDataInvalid)
        verify(parsedInvalid === null)
    }

    function test_parseAmdGpu() {
        var ru = ResourceUsage

        // sysfs fallback format: busy%, temp_millideg, vram_used_bytes, vram_total_bytes
        // e.g. AMD card at 37% busy, 52°C, 2 GiB used of 8 GiB
        var amdData = "37 52000 2147483648 8589934592\n"
        var parsed = ru.parseAmdGpu(amdData)
        verify(parsed !== null)
        compare(parsed.gpuTemp, 52) // millidegrees -> °C
        compare(parsed.gpuUsage, 0.37) // 37% -> 0.37
        compare(parsed.vramUsed, 2147483648 / 1024) // bytes -> KB
        compare(parsed.vramTotal, 8589934592 / 1024)

        // Intel iGPU: no gpu_busy_percent (0) and no VRAM counters (0), temp only
        var intelData = "0 45000 0 0\n"
        var parsedIntel = ru.parseAmdGpu(intelData)
        verify(parsedIntel !== null)
        compare(parsedIntel.gpuTemp, 45)
        compare(parsedIntel.gpuUsage, 0)
        compare(parsedIntel.vramUsed, 0)
        compare(parsedIntel.vramTotal, 1) // guarded against divide-by-zero

        // Invalid output
        var amdDataInvalid = "no gpu here"
        var parsedInvalid = ru.parseAmdGpu(amdDataInvalid)
        verify(parsedInvalid === null)
    }

    function test_parseHwmonTemp() {
        var ru = ResourceUsage

        // hwmon temp*_input is millidegrees Celsius
        compare(ru.parseHwmonTemp("48875\n"), 48.875)
        compare(ru.parseHwmonTemp("52000"), 52)

        // Unreadable file / garbage is null, not a confident zero
        verify(ru.parseHwmonTemp("") === null)
        verify(ru.parseHwmonTemp("garbage") === null)
    }

    function test_parseProbes_nvidia() {
        var ru = ResourceUsage
        var p = ru.parseProbes(
            "cputemp /sys/class/hwmon/hwmon5/temp1_input\n" +
            "gpu nvidia pm=/sys/bus/pci/devices/0000:01:00.0/power/runtime_status\n")
        compare(p.cpuTempPath, "/sys/class/hwmon/hwmon5/temp1_input")
        compare(p.gpuVendor, "nvidia")
        compare(p.nvidiaPmPath, "/sys/bus/pci/devices/0000:01:00.0/power/runtime_status")
    }

    function test_parseProbes_amd() {
        var ru = ResourceUsage
        var p = ru.parseProbes(
            "cputemp -\n" +
            "gpu amd busy=/sys/a/gpu_busy_percent temp=/sys/a/temp1_input" +
            " vramu=/sys/a/mem_info_vram_used vramt=/sys/a/mem_info_vram_total\n")
        // '-' means no hwmon CPU temp source was found
        compare(p.cpuTempPath, "")
        compare(p.gpuVendor, "amd")
        compare(p.gpuPaths.busy, "/sys/a/gpu_busy_percent")
        compare(p.gpuPaths.temp, "/sys/a/temp1_input")
        compare(p.gpuPaths.vramUsed, "/sys/a/mem_info_vram_used")
        compare(p.gpuPaths.vramTotal, "/sys/a/mem_info_vram_total")
    }

    function test_parseProbes_none_and_noise() {
        var ru = ResourceUsage
        var p = ru.parseProbes("something unexpected\ngpu none\n")
        compare(p.gpuVendor, "")
        compare(p.cpuTempPath, "")
        compare(p.nvidiaPmPath, "")

        var empty = ru.parseProbes("")
        compare(empty.gpuVendor, "")
    }

    function test_parseProbes_nvidia_without_pm_path() {
        var ru = ResourceUsage
        // A driver stack with no PCI runtime-status file: still nvidia, no gate
        var p = ru.parseProbes("gpu nvidia pm=-\n")
        compare(p.gpuVendor, "nvidia")
        compare(p.nvidiaPmPath, "")
    }

    function test_nvidiaShouldPoll() {
        var ru = ResourceUsage

        // Awake (or waking): polling costs nothing extra
        verify(ru.nvidiaShouldPoll("active\n"))
        verify(ru.nvidiaShouldPoll("resuming"))

        // Runtime-suspended: an nvidia-smi run would WAKE the GPU - never poll
        verify(!ru.nvidiaShouldPoll("suspended\n"))
        verify(!ru.nvidiaShouldPoll("suspending"))

        // No runtime-status file (desktops, older kernels): keep polling
        verify(ru.nvidiaShouldPoll(""))
    }

    function test_parseAmdSysfs() {
        var ru = ResourceUsage

        // Four raw sysfs file contents in, same shape as parseAmdGpu out
        var p = ru.parseAmdSysfs("37\n", "52000\n", "2147483648\n", "8589934592\n")
        verify(p !== null)
        compare(p.gpuTemp, 52)
        compare(p.gpuUsage, 0.37)
        compare(p.vramUsed, 2147483648 / 1024)
        compare(p.vramTotal, 8589934592 / 1024)

        // Intel iGPU: no busy file, no VRAM counters - temp still reports
        var intel = ru.parseAmdSysfs("", "45000\n", "", "")
        verify(intel !== null)
        compare(intel.gpuTemp, 45)
        compare(intel.gpuUsage, 0)

        // Nothing readable at all is null, not zeros
        verify(ru.parseAmdSysfs("", "", "", "") === null)
    }
}
