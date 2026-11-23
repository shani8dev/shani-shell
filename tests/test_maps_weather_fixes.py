"""Static checks for the maps/weather fixes (no QML runtime in this suite)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPS = (ROOT / "shani/Modules/Maps/MapsPanel.qml").read_text(encoding="utf-8")
WEATHER = (ROOT / "shani/Modules/Weather/WeatherWindow.qml").read_text(encoding="utf-8")


def test_location_buttons_explain_why_they_did_nothing():
    assert "property bool locationAsked: false" in MAPS
    note = MAPS[
        MAPS.index("readonly property string locationNote") : MAPS.index(
            "property string searchError"
        )
    ]
    for reason in (
        "Location.running",
        "Location.error",
        "Settings.data.useLocation",
        "Location.available",
    ):
        assert reason in note
    assert "win.locationAsked = true" in MAPS
    assert 'visible: win.locationNote !== ""' in MAPS


def test_directions_link_is_not_built_without_a_start():
    route = MAPS[
        MAPS.index("readonly property string routeUrl") : MAPS.index(
            "// the place found"
        )
    ]
    assert 'if (from === "")\n            return "";' in route
    assert "readonly property bool fromOk" in MAPS


def test_a_search_typed_during_one_in_flight_is_queued():
    fn = MAPS[MAPS.index("function geoCode(query)") : MAPS.index("searchField = q;")]
    assert "if (searching) {" in fn
    assert "pendingGeo = q;" in fn
    assert "geoThrottle.restart();" in fn
    throttle = MAPS[
        MAPS.index("id: geoThrottle") : MAPS.index("readonly property string routeUrl")
    ]
    assert "const q = win.pendingGeo;" in throttle
    assert "if (q) win.geoCode(q);" in throttle


def test_weather_only_saves_a_typed_city_with_coordinates_once():
    ready = WEATHER[
        WEATHER.index("readonly property bool currentCityReady") : WEATHER.index(
            "onVisibleChanged"
        )
    ]
    assert 'Settings.data.weatherCity !== ""' in ready
    assert "Settings.data.weatherLat !== 0 || Settings.data.weatherLon !== 0" in ready
    saved = WEATHER[
        WEATHER.index("readonly property bool currentCitySaved") : WEATHER.index(
            "onVisibleChanged"
        )
    ]
    assert "Weather.places.some(" in saved
    assert "enabled: win.currentCityReady && !win.currentCitySaved" in WEATHER


def test_weather_waiting_for_location_is_not_a_generic_question():
    empty = WEATHER[WEATHER.index('visible: Weather.summary === ""') :]
    assert "Weather.enabled || Location.running" in empty
    assert 'Location.running ? Tr.t("Find my location") + "…"' in empty
    assert 'Location.error !== "" ? Location.error' in empty
