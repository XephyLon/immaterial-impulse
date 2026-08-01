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
}
