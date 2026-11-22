"""Weather gaps: multiple saved locations + search, dayparts, more than 7 days."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVC = (ROOT / "shani/Services/Weather.qml").read_text()
WINDOW = (ROOT / "shani/Modules/Weather/WeatherWindow.qml").read_text()


def test_multiple_saved_locations_persisted_and_selected():
    assert "property var places: []" in SVC and "property int activePlace: 0" in SVC
    assert "weather-places.json" in SVC and "placesSave.restart()" in SVC
    for fn in (
        "currentLat()",
        "currentLon()",
        "currentName()",
        "selectPlace(",
        "addPlace(",
        "removePlace(",
    ):
        assert f"function {fn}" in SVC, fn
    assert '&latitude=" + lat' in SVC and '&longitude=" + lon' in SVC
    assert "Weather.places" in WINDOW and "Weather.selectPlace(index)" in WINDOW
    assert (
        "Weather.removePlace(index)" in WINDOW
        and "Weather.activePlace === index" in WINDOW
    )


def test_in_app_city_search():
    assert "function searchCity(" in SVC and "count=5&name=" in SVC
    assert "property var searchResults: []" in SVC and "searchError" in SVC
    assert "id: geoSearch" in SVC and "root.searchResults = rs.map" in SVC
    assert (
        "id: citySearch" in WINDOW and "Weather.searchCity(citySearch.text)" in WINDOW
    )
    assert "Weather.searchResults" in WINDOW and "Weather.addPlace(modelData)" in WINDOW
    assert "No city found" in SVC


def test_dayparts_from_hourly_points():
    assert "property var dayparts: []" in SVC
    assert "function buildDayparts(" in SVC
    for part in ("morning", "afternoon", "evening", "night"):
        assert f'"{part}"' in SVC, part
        assert f'Tr.t("{part.capitalize()}")' in SVC, part
    assert "root.dayparts = root.buildDayparts(h)" in SVC
    assert "Weather.dayparts" in WINDOW and "modelData.label" in WINDOW
    assert "modelData.hi" in WINDOW and "modelData.lo" in WINDOW


def test_more_than_seven_days():
    assert "property int forecastDays: 7" in SVC
    assert '"&past_days=0&forecast_days=" + forecastDays' in SVC
    assert "Math.min(d.time.length, root.forecastDays)" in SVC
    assert "Weather.forecastDays = modelData" in WINDOW
    assert "[7, 10, 14, 16]" in WINDOW
