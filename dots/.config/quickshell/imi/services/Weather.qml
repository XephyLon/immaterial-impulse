pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root

    // 10 minute
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    property bool gpsActive: Config.options.bar.weather.enableGPS

    // "owm" (OpenWeatherMap, needs an API key) or "wttr" (wttr.in, keyless)
    readonly property string provider: Config.options.bar.weather.provider ?? "owm"
    // User-supplied OpenWeatherMap key; empty falls back to the built-in one below
    readonly property string apiKey: Config.options.bar.weather.apiKey ?? ""
    // Built-in fallback so existing users keep working with no key configured
    readonly property string owmFallbackApiKey: "8b05d62206f459e1d298cbe5844d7d87"

    onUseUSCSChanged: root.getData()
    onCityChanged: root.getData()
    onProviderChanged: root.getData()
    onApiKeyChanged: root.getData()

    property var location: ({
        valid: false,
        lat: 0,
        lon: 0
    })

    property var data: ({
        uv: 0,
        humidity: 0,
        sunrise: 0,
        sunset: 0,
        windDir: 0,
        wCode: 0,
        city: "",
        wind: "",
        precip: "",
        visib: "",
        press: "",
        temp: "",
        tempFeelsLike: "",
        tempHigh: "",
        tempLow: "",
        lastRefresh: ""
    })

    function refineData(data) {
        let temp = {}
        const rainMm = data?.rain?.["1h"] || data?.rain?.["3h"] || 0
        const snowMm = data?.snow?.["1h"] || data?.snow?.["3h"] || 0

        temp.description = data?.weather?.[0]?.description || ""
        temp.cr = data?.clouds?.all !== undefined
            ? Math.round(data.clouds.all * 0.8) + "%"
            : "0%"
        temp.humidity = (data?.main?.humidity || 0) + "%"

        const fmt = (unix) => new Date(unix * 1000).toLocaleTimeString("en-US", {
            hour: "numeric",
            minute: "2-digit",
            second: "2-digit",
            hour12: true
        })

        temp.sunrise = data?.sys?.sunrise ? fmt(data.sys.sunrise) : "0"
        temp.sunset  = data?.sys?.sunset  ? fmt(data.sys.sunset)  : "0"

        temp.windDir = data?.wind?.deg || 0
        temp.wCode = data?.weather?.[0]?.id || 0
        temp.city = data?.name || "City"

        if (root.useUSCS) {
            temp.wind = (data?.wind?.speed || 0) + " mph"
            temp.precip = ((rainMm + snowMm) * 0.0394).toFixed(2) + " in"
            temp.visib = ((data?.visibility || 0) / 1609).toFixed(1) + " mi"
            temp.press = (data?.main?.pressure || 0) + " hPa"
            temp.temp = Math.round(data?.main?.temp || 0) + "°F"
            temp.tempFeelsLike = Math.round(data?.main?.feels_like || 0) + "°F"
            temp.tempHigh = Math.round(data?.main?.temp_max || 0) + "°F"
            temp.tempLow = Math.round(data?.main?.temp_min || 0) + "°F"
        } else {
            temp.wind = (data?.wind?.speed || 0) + " m/s"
            temp.precip = (rainMm + snowMm).toFixed(1) + " mm"
            temp.visib = ((data?.visibility || 0) / 1000).toFixed(1) + " km"
            temp.press = (data?.main?.pressure || 0) + " hPa"
            let roundedTemp = Math.round(data?.main?.temp || 0)
            let roundedFeels = Math.round(data?.main?.feels_like || 0)

            temp.temp = roundedTemp + "°C"
            temp.tempFeelsLike = roundedFeels + "°C"
            temp.tempHigh = Math.round(data?.main?.temp_max || 0) + "°C"
            temp.tempLow = Math.round(data?.main?.temp_min || 0) + "°C"
        }

        temp.lastRefresh = DateTime.time + " • " + DateTime.date

        root.data = temp
    }

    // wttr.in's ?format=j1 response, mapped into the same output shape as refineData.
    // Note: wttr.in already uses the WWO weather codes that Icons.weatherIconMap keys
    // on, so weatherCode maps straight to wCode with no translation needed.
    function refineWttrData(data) {
        let temp = {}
        const current = data?.current_condition?.[0] || {}
        const today = data?.weather?.[0] || {}
        const astro = today?.astronomy?.[0] || {}

        temp.description = current?.weatherDesc?.[0]?.value || ""
        temp.cr = (current?.cloudcover || 0) + "%"
        temp.humidity = (current?.humidity || 0) + "%"

        // wttr.in gives already-formatted local times (e.g. "06:14 AM")
        temp.sunrise = astro?.sunrise || "0"
        temp.sunset = astro?.sunset || "0"

        temp.windDir = Number(current?.winddirDegree || 0)
        temp.wCode = Number(current?.weatherCode || 0)
        temp.city = data?.nearest_area?.[0]?.areaName?.[0]?.value || "City"

        if (root.useUSCS) {
            temp.wind = (current?.windspeedMiles || 0) + " mph"
            temp.precip = (Number(current?.precipMM || 0) * 0.0394).toFixed(2) + " in"
            temp.visib = (current?.visibilityMiles || 0) + " mi"
            temp.press = (current?.pressure || 0) + " hPa"
            temp.temp = Math.round(Number(current?.temp_F || 0)) + "°F"
            temp.tempFeelsLike = Math.round(Number(current?.FeelsLikeF || 0)) + "°F"
            temp.tempHigh = Math.round(Number(today?.maxtempF || 0)) + "°F"
            temp.tempLow = Math.round(Number(today?.mintempF || 0)) + "°F"
        } else {
            temp.wind = (current?.windspeedKmph || 0) + " km/h"
            temp.precip = Number(current?.precipMM || 0).toFixed(1) + " mm"
            temp.visib = (current?.visibility || 0) + " km"
            temp.press = (current?.pressure || 0) + " hPa"
            temp.temp = Math.round(Number(current?.temp_C || 0)) + "°C"
            temp.tempFeelsLike = Math.round(Number(current?.FeelsLikeC || 0)) + "°C"
            temp.tempHigh = Math.round(Number(today?.maxtempC || 0)) + "°C"
            temp.tempLow = Math.round(Number(today?.mintempC || 0)) + "°C"
        }

        temp.lastRefresh = DateTime.time + " • " + DateTime.date

        root.data = temp
    }

    function getData() {
        if (root.provider === "wttr") {
            getDataWttr()
            return
        }
        getDataOwm()
    }

    function getDataOwm() {
        // Empty user key falls back to the built-in one, so nothing breaks by default
        let apiKey = root.apiKey !== "" ? root.apiKey : root.owmFallbackApiKey

        if (apiKey === "") {
            console.error("[WeatherService] Missing OpenWeather API key.")
            return
        }

        let units = root.useUSCS ? "imperial" : "metric"
        let url = "https://api.openweathermap.org/data/2.5/weather?"

        if (root.gpsActive && root.location.valid) {
            url += `lat=${root.location.lat}&lon=${root.location.lon}`
        } else {
            url += `q=${formatCityName(root.city)}`
        }

        url += `&units=${units}`
        url += `&appid=${apiKey}`

        // Pass the URL as a curl argv element, not through a shell: city flows
        // from config (and shareable presets) and was spliced into a double-quoted
        // `curl -s "${url}"` where $()/backticks still expand - a command-injection
        // hole. curl receives the URL literally here, no shell parsing.
        fetcher.command = ["curl", "-s", url]
        fetcher.running = true
    }

    function getDataWttr() {
        let loc
        if (root.gpsActive && root.location.valid) {
            loc = `${root.location.lat},${root.location.lon}`
        } else {
            loc = formatCityName(root.city)
        }

        let url = `https://wttr.in/${loc}?format=j1`

        // Same hardening as the OWM path: the location (from config/presets) is
        // only ever a curl argv element, never spliced into a shell string.
        fetcher.command = ["curl", "-s", url]
        fetcher.running = true
    }

    function formatCityName(cityName) {
        return cityName.trim().split(/\s+/).join('+')
    }

    Component.onCompleted: {
        if (!root.gpsActive) return
        console.info("[WeatherService] Starting GPS service.")
        positionSource.start()
    }

    Process {
        id: fetcher
        command: ["curl", "-s", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return

                try {
                    const parsedData = JSON.parse(text)

                    if (root.provider === "wttr") {
                        if (!parsedData.current_condition || parsedData.current_condition.length === 0) {
                            console.error("[WeatherService] wttr.in returned no usable data.")
                            return
                        }
                        root.refineWttrData(parsedData)
                        return
                    }

                    if (parsedData.cod && parsedData.cod !== 200) {
                        console.error("[WeatherService] API error:", parsedData.message)
                        return
                    }

                    root.refineData(parsedData)
                } catch (e) {
                    console.error("[WeatherService] JSON parse error:", e.message)
                }
            }
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                root.location.lat = position.coordinate.latitude
                root.location.lon = position.coordinate.longitude
                root.location.valid = true
                root.getData()
            } else {
                root.gpsActive = root.location.valid ? true : false
                console.error("[WeatherService] Failed to get GPS location.")
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop()
                root.location.valid = false
                root.gpsActive = false
                console.error("[WeatherService] Could not acquire valid GPS backend.")
            }
        }
    }

    Timer {
        running: !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: !root.gpsActive
        onTriggered: root.getData()
    }
}
