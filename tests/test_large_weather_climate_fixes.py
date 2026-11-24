"""Static checks for the Weather "climate companion" upgrade.

There is no QML runtime in this suite; each non-trivial branch is checked in
the source of the two files that own it (service and window).
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = (ROOT / "shani/Services/Weather.qml").read_text(encoding="utf-8")
WINDOW = (ROOT / "shani/Modules/Weather/WeatherWindow.qml").read_text(encoding="utf-8")


def test_units_are_owned_and_persisted_by_the_service():
    for text in (
        'property string units: Settings.data.weatherUnits === "fahrenheit"',
        'path: Quickshell.statePath("weather-prefs.json")',
        "function setUnits(u)",
        "prefsSave.restart()",
        "onUnitsChanged: root.fetch()",
        "if (Settings.data.weatherUnits !== next) Settings.data.weatherUnits = next;",
    ):
        assert text in SERVICE, text
    assert 'Weather.setUnits("celsius")' in WINDOW
    assert 'Weather.setUnits("fahrenheit")' in WINDOW


def test_units_convert_wind_and_visibility_too():
    for text in (
        'readonly property string windUnit: fahrenheit ? "mph" : "km/h"',
        'readonly property string distanceUnit: fahrenheit ? "mi" : "km"',
        "function windValue(v)",
        "function distanceValue(v)",
        "0.621371",
        "1609.344",
    ):
        assert text in SERVICE, text
    assert "Weather.windValue(Weather.wind)" in WINDOW
    assert "Weather.distanceValue(Weather.visibility)" in WINDOW
    assert "Weather.windValue(modelData.wind)" in WINDOW


def test_hourly_graph_draws_temperature_and_rain():
    assert "win.rainCurve" in WINDOW
    assert "values: win.tempCurve" in WINDOW
    assert "values: win.rainCurve" in WINDOW
    assert 'Accessible.name: Tr.t("Temperature and rain, next 24 hours")' in WINDOW
    assert "win.graphRange" in WINDOW
    assert 'Text { text: Tr.t("Rain chance")' in WINDOW


def test_service_fetches_daily_fields_for_collapsible_detail():
    for text in (
        "precipitation_probability_max,wind_speed_10m_max,uv_index_max",
        "rain: (d.precipitation_probability_max || [])[i] || 0",
        "wind: (d.wind_speed_10m_max || [])[i] || 0",
        "uv: (d.uv_index_max || [])[i] || 0",
        'sunrise: String((d.sunrise || [])[i] || "").slice(11, 16)',
    ):
        assert text in SERVICE, text


def test_multi_day_outlook_has_collapsible_detail():
    assert "property int expandedDay: -1" in WINDOW
    assert "function toggleDay(i)" in WINDOW
    assert (
        'text: win.expandedDay === dayRow.index ? Tr.t("Hide") : Tr.t("Details")'
        in WINDOW
    )
    assert "win.toggleDay(dayRow.index)" in WINDOW
    assert "win.expandedDay < Weather.forecast.length" in WINDOW
    detail = WINDOW[WINDOW.index("// one expanded day at a time") :]
    for text in (
        'Tr.t("Chance of rain")',
        'Tr.t("Max wind")',
        'Tr.t("Max UV")',
        'Tr.t("Sun")',
        "Weather.uvLevel(modelData.uv)",
        "modelData.sunrise",
    ):
        assert text in detail, text


def test_alerts_are_graded_and_labelled_as_forecast_guidance():
    for text in (
        "property var alerts: []",
        "function buildAlerts(next)",
        'level: "warning"',
        'level: "advisory"',
        "root.alerts = root.buildAlerts(hours.slice(0, 12))",
        'readonly property string advisory: alerts.length ? alerts[0].label : ""',
    ):
        assert text in SERVICE, text
    assert "model: Weather.alerts" in WINDOW
    assert 'modelData.level === "warning" ? Theme.danger : Theme.amber' in WINDOW
    assert 'Tr.t("Based on the forecast, not an official warning")' in WINDOW
    assert 'Accessible.name: modelData.label + ", " + modelData.detail' in WINDOW


def test_uv_index_and_air_quality_are_optional_but_rendered():
    for text in (
        "property real uvIndex: NaN",
        "property real aqi: NaN",
        "property real pm25: NaN",
        "readonly property string uvText:",
        "readonly property string aqiText:",
        "function uvLevel(v)",
        "function aqiLevel(v)",
        "surface_pressure,visibility,uv_index",
        "air-quality-api.open-meteo.com/v1/air-quality?current=us_aqi,pm2_5",
        "id: air",
        "root.aqi = a.us_aqi",
        "root.pm25 = a.pm2_5",
    ):
        assert text in SERVICE, text
    assert "Weather.uvText" in WINDOW and "Weather.aqiText" in WINDOW
    assert 'Tr.t("Air quality by Open-Meteo")' in WINDOW


def test_location_search_reports_work_in_progress_and_failure():
    assert "property bool searchBusy: false" in SERVICE
    assert "searchBusy = true;" in SERVICE
    assert "onExited: code => {" in SERVICE
    assert 'root.searchError = Tr.t("City search failed")' in SERVICE
    assert 'text: Weather.searchBusy ? Tr.t("Searching…") : Tr.t("Search")' in WINDOW
    assert 'visible: Weather.searchError !== ""' in WINDOW


def test_saved_places_can_be_renamed_reordered_and_not_duplicated():
    for text in (
        "function renamePlace(i, name)",
        "function movePlace(i, delta)",
        'searchError = Tr.t("Already saved")',
        "m[i] = Object.assign({}, m[i], { name: n })",
        "if (activePlace === i) activePlace = j;",
        "placesSave.restart();",
    ):
        assert text in SERVICE, text
    for text in (
        "Weather.renamePlace(index,",
        "Weather.movePlace(index, -1)",
        "Weather.movePlace(index, 1)",
        "win.renameIndex === index",
        'tip: Tr.t("Rename location")',
    ):
        assert text in WINDOW, text


def test_auto_refresh_shows_when_the_data_was_last_updated():
    for text in (
        "property int updatedMs: 0",
        'property string lastUpdated: ""',
        "Qt.formatTime(new Date(root.updatedMs)",
        "readonly property string updatedText:",
        "readonly property int refreshMinutes: 30",
        "interval: refreshMinutes * 60 * 1000",
    ):
        assert text in SERVICE, text
    assert "Weather.updatedText" in WINDOW
    assert 'Tr.t(" · auto-refresh every %1 min", Weather.refreshMinutes)' in WINDOW


def test_offline_refresh_keeps_stale_values_with_an_as_of_label():
    assert "property bool loading: false" in SERVICE
    assert "loading = true;" in SERVICE
    assert 'readonly property bool stale: error !== "" && updatedMs > 0' in SERVICE
    assert "root.loading = false;" in SERVICE
    assert "Weather.stale" in WINDOW
    assert 'Tr.t("Showing last known weather")' in WINDOW
    assert (
        'Button { text: Tr.t("Retry"); flat: true; onClicked: Weather.fetch() }'
        in WINDOW
    )
    assert 'title: Weather.error !== "" ? Tr.t("Weather unavailable")' in WINDOW


def test_keyboard_refresh_and_focusable_controls():
    assert "Keys.onPressed: e => {" in WINDOW
    assert "Qt.Key_F5" in WINDOW
    assert "Qt.ControlModifier" in WINDOW
    # the existing arrow-key lists stay keyboard reachable
    assert WINDOW.count("KeyFocus { }") >= 2
    assert 'Accessible.name: modelData.hour + ", "' in WINDOW
    assert "Accessible.name: dayRow.modelData.day +" in WINDOW
    assert "Accessible.role: Accessible.Graphic" in WINDOW


def test_new_controls_have_accessible_names():
    for text in (
        'Accessible.name: Tr.t("Showing last known weather")',
        'Accessible.name: modelData.label + ", " + modelData.detail',
        'Accessible.name: modelData.label + ", " + Math.round(modelData.hi)',
        "Accessible.name: text",
        'Accessible.name: (win.expandedDay === dayRow.index ? Tr.t("Hide details for")',
    ):
        assert text in WINDOW, text


def test_a_long_forecast_scrolls_instead_of_being_clipped():
    assert "Flickable {" in WINDOW
    assert "contentHeight: contentCol.implicitHeight" in WINDOW
    assert "id: contentCol" in WINDOW
    assert "width: parent.width" in WINDOW


def test_qml_braces_are_balanced():
    for name, source in (("service", SERVICE), ("window", WINDOW)):
        assert source.count("{") == source.count("}"), name
