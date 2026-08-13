.pragma library

// Which google-weather asset a weather code draws as.
//
// The desktop card renders `CustomIcon`s from assets/icons/google-weather,
// which is a different vocabulary from the Material Symbol names
// `Icons.getProviderWeatherIcon` returns for the bar - #111 declined to unify
// them for exactly that reason, since sharing them is a port rather than a
// rename. This is the card's own half of the same lesson.
//
// The lesson being: **a weather code means nothing without the provider that
// reported it.** `Weather.data.wCode` carries OpenWeatherMap condition ids on
// the `owm` provider and World Weather Online codes on `wttr`, and the card
// resolved every one of them through an OWM-shaped range table. The schemes
// overlap numerically, so that is not merely a miss - WWO 113 is Sunny and
// falls past every OWM range into "cloudy", while WWO 296 is Light rain and
// lands inside OWM's 2xx thunderstorm range and comes back confidently as a
// storm. Nothing about it is visible in a log.
//
// The OWM branch is deliberately the card's existing expression unchanged.
// It is what ships today on the default provider, and retuning it is a
// separate question from giving the other provider a table at all.

function glyphFor(provider, code, night) {
    return provider === "owm" ? _owm(code, night) : _wwo(code, night);
}

function _owm(code, night) {
    var id = Number(code);
    if (id === 800) return night ? "clear_night" : "clear_day";
    if (id === 801) return night ? "partly_cloudy_night" : "partly_cloudy_day";
    if (id >= 200 && id < 300) return "strong_thunderstorms";
    if (id >= 300 && id < 600) return "heavy_rain";
    if (id >= 600 && id < 700) return "heavy_snow";
    if (id >= 700 && id < 800) return "haze_fog_dust_smoke";
    return "cloudy";
}

// World Weather Online's codes, which wttr.in speaks. Sparse and unordered -
// they are not ranges, so this is a table rather than a chain of comparisons,
// and a code that is not in it degrades to "cloudy" exactly as the OWM branch
// does for an unrecognised id.
//
// `_DAY_NIGHT` are the entries whose asset comes in two variants; everything
// else looks the same after dark.
var _DAY_NIGHT = {
    113: "clear",
    116: "partly_cloudy",
    119: "mostly_cloudy",
    176: "scattered_showers",
    179: "scattered_snow_showers",
    200: "isolated_scattered_thunderstorms",
    353: "scattered_showers",
    368: "scattered_snow_showers",
    386: "isolated_scattered_thunderstorms",
    392: "isolated_scattered_thunderstorms"
};

var _FIXED = {
    122: "cloudy",
    143: "haze_fog_dust_smoke",
    182: "mixed_rain_snow",
    185: "icy",
    227: "blowing_snow",
    230: "blizzard",
    248: "haze_fog_dust_smoke",
    260: "haze_fog_dust_smoke",
    263: "drizzle",
    266: "drizzle",
    281: "icy",
    284: "icy",
    293: "showers_rain",
    296: "showers_rain",
    299: "showers_rain",
    302: "showers_rain",
    305: "heavy_rain",
    308: "heavy_rain",
    311: "icy",
    314: "icy",
    317: "sleet_hail",
    320: "sleet_hail",
    323: "flurries",
    326: "flurries",
    329: "showers_snow",
    332: "showers_snow",
    335: "heavy_snow",
    338: "heavy_snow",
    350: "sleet_hail",
    356: "showers_rain",
    359: "heavy_rain",
    362: "mixed_rain_snow",
    365: "mixed_rain_snow",
    371: "showers_snow",
    374: "sleet_hail",
    377: "sleet_hail",
    389: "strong_thunderstorms",
    395: "strong_thunderstorms"
};

function _wwo(code, night) {
    var key = String(Number(code));
    if (_DAY_NIGHT.hasOwnProperty(key))
        return _DAY_NIGHT[key] + (night ? "_night" : "_day");
    if (_FIXED.hasOwnProperty(key))
        return _FIXED[key];
    return "cloudy";
}
