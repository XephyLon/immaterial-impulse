import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell.Io
import "bar_popup_unroll.js" as BarPopupUnroll

StyledPopup {
    id: root

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    Row {
        spacing: Appearance.spacing.space100

        // The first column is this popup's HERO: the card opens at its
        // height, so RAM and CPU are legible on frame one and it never
        // declares `appear`. The other two columns are the below-the-fold
        // sections that cascade in on BarPopupOverlay's gated wave -
        // rightward here rather than downward, because this popup's sections
        // run across the card.
        Column {
            id: ramCpuColumn
            spacing: Appearance.spacing.space100

            ResourceCard {
                label: "RAM"
                iconText: "memory"
                iconShape: MaterialShape.Shape.Clover4Leaf
                value: ResourceUsage.memoryUsed / ResourceUsage.memoryTotal
                sublabel: root.formatKB(ResourceUsage.memoryUsed) + " / " + root.formatKB(ResourceUsage.memoryTotal)
            }

            ResourceCard {
                label: "CPU"
                iconText: "planner_review"
                iconShape: MaterialShape.Shape.Gem
                value: ResourceUsage.cpuUsage
                sublabel: `${Math.round(ResourceUsage.cpuTemp)}°C`
                sublabelColor: ResourceUsage.cpuTemp > 80 ? Appearance.colors.colError
                    : ResourceUsage.cpuTemp > 60 ? Appearance.m3colors.m3tertiary
                    : Appearance.colors.colOnLayer1
            }
        }

        Column {
            id: swapDiskColumn
            property real appear: 1
            opacity: swapDiskColumn.appear
            scale: BarPopupUnroll.entranceScale(swapDiskColumn.appear, root.entranceRise, swapDiskColumn.width)
            transform: Translate { y: BarPopupUnroll.entranceOffset(swapDiskColumn.appear, root.entranceRise) }
            spacing: Appearance.spacing.space100

            ResourceCard {
                label: "Swap"
                iconText: "swap_horiz"
                iconShape: MaterialShape.Shape.Bun
                value: ResourceUsage.swapUsedPercentage
                sublabel: root.formatKB(ResourceUsage.swapUsed) + " / " + root.formatKB(ResourceUsage.swapTotal)
            }

            ResourceCard {
                label: "Disk"
                iconText: "hard_drive"
                iconShape: MaterialShape.Shape.Circle
                value: ResourceUsage.diskUsedPercentage
                sublabel: root.formatKB(ResourceUsage.diskUsed) + " / " + root.formatKB(ResourceUsage.diskTotal)
            }
        }

        Column {
            id: gpuColumn
            property real appear: 1
            opacity: gpuColumn.appear
            scale: BarPopupUnroll.entranceScale(gpuColumn.appear, root.entranceRise, gpuColumn.width)
            transform: Translate { y: BarPopupUnroll.entranceOffset(gpuColumn.appear, root.entranceRise) }
            spacing: Appearance.spacing.space100

            ResourceCard {
                label: "GPU"
                iconText: "monitor"
                iconShape: MaterialShape.Shape.ClamShell
                value: ResourceUsage.gpuUsage
                sublabel: `${Math.round(ResourceUsage.gpuTemp)}°C`
                sublabelColor: ResourceUsage.gpuTemp > 80 ? Appearance.colors.colError
                    : ResourceUsage.gpuTemp > 60 ? Appearance.m3colors.m3tertiary
                    : Appearance.colors.colOnLayer1
            }

            ResourceCard {
                label: "VRAM"
                iconText: "memory"
                iconShape: MaterialShape.Shape.Clover4Leaf
                value: ResourceUsage.vramUsedPercentage
                sublabel: root.formatKB(ResourceUsage.vramUsed) + " / " + root.formatKB(ResourceUsage.vramTotal)
            }
        }
    }
}