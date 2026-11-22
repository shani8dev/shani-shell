"""Weather shows the conditions the API already fetches, not just a number."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = (ROOT / "shani/Services/Weather.qml").read_text()
WINDOW = (ROOT / "shani/Modules/Weather/WeatherWindow.qml").read_text()


def test_service_fetches_and_stores_current_details():
    for field in (
        "apparent_temperature",
        "relative_humidity_2m",
        "wind_speed_10m",
        "surface_pressure",
        "visibility",
    ):
        assert field in SERVICE, field
    assert "sunrise,sunset" in SERVICE
    for prop in (
        "feelsLike",
        "humidity",
        "wind",
        "pressure",
        "visibility",
        "sunrise",
        "sunset",
    ):
        assert f"property" in SERVICE and prop in SERVICE, prop
    assert "root.feelsLike = c.apparent_temperature" in SERVICE
    assert "root.sunrise = String(d.sunrise[0]).slice(11, 16)" in SERVICE


def test_window_renders_details_and_hourly_rain():
    for label in ("Feels like", "Humidity", "Wind", "Pressure", "Visibility"):
        assert f'Tr.t("{label}")' in WINDOW, label
    assert "Weather.sunrise" in WINDOW and "Weather.sunset" in WINDOW
    assert "modelData.rain" in WINDOW
