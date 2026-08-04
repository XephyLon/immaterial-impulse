pragma Singleton
// From https://github.com/caelestia-dots/shell (GPLv3)
import Quickshell
import QtQml

Singleton {
    id: root

    function getDesktopActionMaterialSymbol(icon: string): string {
        // Some apps ship custom icon names in their desktop-entry actions
        // (e.g. VS Code uses "vscode", others use freedesktop names).
        // Map known cases to Material Symbols; fall through unchanged otherwise.
        switch (icon) {
            case "vscode": return "code";
            case "application-exit": return "exit_to_app";
        }
        return icon;
    }

    function getBluetoothDeviceMaterialSymbol(systemIconName: string): string {
        if (systemIconName.includes("headset") || systemIconName.includes("headphones"))
            return "headphones";
        if (systemIconName.includes("audio"))
            return "speaker";
        if (systemIconName.includes("phone"))
            return "smartphone";
        if (systemIconName.includes("mouse"))
            return "mouse";
        if (systemIconName.includes("keyboard"))
            return "keyboard";
        return "bluetooth";
    }

    function isNight(): bool {
        const hour = new Date().getHours();
        return hour < 6 || hour >= 20;
    }

    readonly property var weatherIconMap: ({
        "113": { day: "clear_day",         night: "clear_night" },
        "116": { day: "partly_cloudy_day", night: "partly_cloudy_night" },
        "119": { day: "cloud",             night: "cloud" },
        "122": { day: "cloud",             night: "cloud" },
        "143": { day: "foggy",             night: "foggy" },
        "176": { day: "rainy",             night: "rainy" },
        "179": { day: "rainy",             night: "rainy" },
        "182": { day: "rainy",             night: "rainy" },
        "185": { day: "rainy",             night: "rainy" },
        "200": { day: "thunderstorm",      night: "thunderstorm" },
        "227": { day: "cloudy_snowing",    night: "cloudy_snowing" },
        "230": { day: "snowing_heavy",     night: "snowing_heavy" },
        "248": { day: "foggy",             night: "foggy" },
        "260": { day: "foggy",             night: "foggy" },
        "263": { day: "rainy",             night: "rainy" },
        "266": { day: "rainy",             night: "rainy" },
        "281": { day: "rainy",             night: "rainy" },
        "284": { day: "rainy",             night: "rainy" },
        "293": { day: "rainy",             night: "rainy" },
        "296": { day: "rainy",             night: "rainy" },
        "299": { day: "rainy",             night: "rainy" },
        "302": { day: "weather_hail",      night: "weather_hail" },
        "305": { day: "rainy",             night: "rainy" },
        "308": { day: "weather_hail",      night: "weather_hail" },
        "311": { day: "rainy",             night: "rainy" },
        "314": { day: "rainy",             night: "rainy" },
        "317": { day: "rainy",             night: "rainy" },
        "320": { day: "cloudy_snowing",    night: "cloudy_snowing" },
        "323": { day: "cloudy_snowing",    night: "cloudy_snowing" },
        "326": { day: "cloudy_snowing",    night: "cloudy_snowing" },
        "329": { day: "snowing_heavy",     night: "snowing_heavy" },
        "332": { day: "snowing_heavy",     night: "snowing_heavy" },
        "335": { day: "snowing",           night: "snowing" },
        "338": { day: "snowing_heavy",     night: "snowing_heavy" },
        "350": { day: "rainy",             night: "rainy" },
        "353": { day: "rainy",             night: "rainy" },
        "356": { day: "rainy",             night: "rainy" },
        "359": { day: "weather_hail",      night: "weather_hail" },
        "362": { day: "rainy",             night: "rainy" },
        "365": { day: "rainy",             night: "rainy" },
        "368": { day: "cloudy_snowing",    night: "cloudy_snowing" },
        "371": { day: "snowing",           night: "snowing" },
        "374": { day: "rainy",             night: "rainy" },
        "377": { day: "rainy",             night: "rainy" },
        "386": { day: "thunderstorm",      night: "thunderstorm" },
        "389": { day: "thunderstorm",      night: "thunderstorm" },
        "392": { day: "thunderstorm",      night: "thunderstorm" },
        "395": { day: "snowing",           night: "snowing" }
    })

    function getWeatherIcon(code): string {
        const key = String(code);
        if (weatherIconMap.hasOwnProperty(key)) {
            const icons = weatherIconMap[key];
            return isNight() ? icons.night : icons.day;
        }
        return isNight() ? "clear_night" : "clear_day";
    }

    // OpenWeatherMap reports its own condition ids, not the WWO codes
    // weatherIconMap is keyed on, so an OWM id looked up there matches nothing
    // and falls through to "clear" for every condition there is. The groups
    // below are OWM's documented ranges; 800 is the only exact id it defines,
    // and 801-804 are increasing cloud cover.
    function getOwmWeatherIcon(code, night): string {
        const id = Number(code);
        if (id === 800) return night ? "clear_night" : "clear_day";
        if (id === 801 || id === 802) return night ? "partly_cloudy_night" : "partly_cloudy_day";
        if (id > 802 && id < 900) return "cloud";
        if (id >= 200 && id < 300) return "thunderstorm";
        if (id >= 300 && id < 400) return "rainy";
        if (id >= 500 && id < 600) return "rainy";
        if (id >= 600 && id < 700) return "snowing";
        if (id >= 700 && id < 800) return "foggy";
        return night ? "clear_night" : "clear_day";
    }

    // Which of the two schemes a code is in depends on which provider fetched
    // it, and nothing in the code itself says - the ranges overlap. Callers that
    // know their provider should come through here rather than guess.
    function getProviderWeatherIcon(provider, code, night): string {
        if (provider === "owm")
            return getOwmWeatherIcon(code, night);
        const key = String(code);
        if (weatherIconMap.hasOwnProperty(key)) {
            const icons = weatherIconMap[key];
            return night ? icons.night : icons.day;
        }
        return night ? "clear_night" : "clear_day";
    }
}