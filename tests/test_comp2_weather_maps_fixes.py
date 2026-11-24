"""Static checks for the comp-2 weather/maps fixes (no QML runtime in this suite)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPS = (ROOT / "shani/Modules/Maps/MapsPanel.qml").read_text(encoding="utf-8")
WEATHER = (ROOT / "shani/Modules/Weather/WeatherWindow.qml").read_text(encoding="utf-8")


def test_weather_hourly_tiles_are_keyboard_reachable():
    hourly = WEATHER[
        WEATHER.index("model: Weather.hourly") : WEATHER.index("// ---- the week ----")
    ]
    assert "Accessible.role: Accessible.ListItem" in hourly
    assert "Accessible.name: modelData.hour" in hourly
    assert "KeyFocus { }" in hourly


def test_weather_week_rows_are_readable_and_focusable():
    week = WEATHER[
        WEATHER.index("// ---- the week ----") : WEATHER.index(
            "Item { Layout.fillHeight: true }"
        )
    ]
    assert "Accessible.role: Accessible.ListItem" in week
    assert "Accessible.name: dayRow.modelData.day" in week
    assert "KeyFocus { }" in week


def test_maps_saved_places_can_be_forgotten_directly():
    assert "function removeSaved(p)" in MAPS
    assert "Settings.data.mapsSaved = saved.filter(" in MAPS
    saved = MAPS[
        MAPS.index("// saved places: one click goes there") : MAPS.index(
            "visible: win.searchError"
        )
    ]
    assert "required property var modelData" in saved
    assert 'icon: "edit-delete"' in saved
    assert "win.removeSaved(parent.modelData)" in saved


def test_maps_start_field_stays_editable_after_a_route():
    start = MAPS[
        MAPS.index("// keep the start editable") : MAPS.index(
            'Button { text: Tr.t("Go")'
        )
    ]
    assert "visible: win.routeAsked" in start
    assert "text: win.routeFrom" in start
    assert "win.fromLat = 0" in start


def test_maps_map_and_location_dot_have_accessible_names():
    grid = MAPS[MAPS.index("id: grid") : MAPS.index("// the route, over the tiles")]
    assert "Accessible.role: Accessible.Pane" in grid
    assert "Accessible.name: win.placeName" in grid
    dot = MAPS[MAPS.index("id: hereDot") : MAPS.index("// two fingers:")]
    # Accessible.Image is not a valid Qt role; graphic is the image role used
    # everywhere else in the shell (Viewer, Photos, QrView, ...)
    assert "Accessible.role: Accessible.Graphic" in dot
    assert "Accessible.Image" not in MAPS
    assert 'Accessible.name: Tr.t("Where you are")' in dot
