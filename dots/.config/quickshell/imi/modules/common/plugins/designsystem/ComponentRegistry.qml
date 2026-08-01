pragma Singleton
import Quickshell

Singleton {
    readonly property string creator: "na-ive / nandoroid-shell"
    readonly property string license: "AGPL-3.0"
    readonly property string sourceUrl: "https://github.com/na-ive/nandoroid-shell"
    readonly property string upstreamRevision: "4994e2d2a264a015d5a6dac4786c60cfe94e5d8a"
    readonly property var categories: ({
        inputs: ["AccentPicker", "AndroidToggle", "ColorPickerButton", "DatePicker", "M3IconButton", "SegmentedButton", "SegmentedWrapper"],
        content: ["AtAGlance", "MediaCard", "UserProfile", "WeatherCard"],
        desktop: ["DesktopCurrencyWidget", "DesktopMediaWidget", "DesktopSystemMonitorWidget", "DesktopWeatherWidget"],
        indicators: ["CavaWidget", "NetworkSpeedMeter", "PrivacyIndicator", "RecordIndicator", "ScrollHint"],
        infrastructure: ["CachingImage", "SearchHandler", "ScreenshotOverlay", "WidgetCanvas"],
        clocks: ["AnalogClock", "CodeClock", "DigitalClock", "NandoClock", "PillClock", "StackedClock", "TextClock"]
    })
}
