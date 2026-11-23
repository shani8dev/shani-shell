"""Static guards for the three pass-20 Maps/navigation fixes.

QML is not compiled in CI; each test pins a source-level invariant so a later
tidy cannot silently undo it. No runtime, network or GeoClue behaviour is
exercised here.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = (ROOT / "shani" / "Modules" / "Maps" / "MapsPanel.qml").read_text(
    encoding="utf-8"
)


def _between(start, end):
    """Source slice from the first `start` marker to the first `end` after it."""
    a = SRC.index(start)
    return SRC[a : SRC.index(end, a)]


def test_osrm_profile_tokens_translated_with_env_override():
    # OSRM's demo server names profiles driving|walking|cycling, not the UI's
    # driving|foot|bike. Translate at the URL and keep the env override.
    profiles = _between("readonly property var routeProfiles", "property bool routing")
    assert "SHANI_MAP_ROUTE_PROFILES" in profiles
    assert '"driving,walking,cycling"' in profiles
    assert 'foot: p[1] || "walking"' in profiles
    assert 'bike: p[2] || "cycling"' in profiles
    directions = _between("function directions()", "function directionsFrom")
    assert "win.routeProfiles[routeProfile]" in directions
    # visible labels and their token values stay as they were
    assert (
        '["driving", Tr.t("Drive")], ["foot", Tr.t("Walk")], ["bike", Tr.t("Cycle")]'
        in SRC
    )


def test_geocode_throttled_and_cached():
    # Nominatim asks for <=1 request/second and repeated queries should be free:
    # a queue timer, a 1 s guard, and a query -> result cache must all exist.
    throttle = _between("id: geoThrottle", "readonly property string routeUrl")
    assert "interval: 1000" in throttle
    assert "pendingGeo" in throttle
    assert "property var geoCache" in SRC
    geo = _between("function geoCode(query)", "function openDirections")
    assert "Date.now() - lastGeoAt < 1000" in geo
    assert "win.geoCache" in geo and "win.applyGeoResult" in geo
    applied = _between("function applyGeoResult(r)", "function geoCode(query)")
    assert "win.mapLat = lat" in applied and "win.pinLon = lon" in applied
    # the network handler stores into the same cache (same async result shape)
    proc = _between("id: geoProc", "onExited: code =>")
    assert "c[win.searchField] = r" in proc and "win.geoCache = c" in proc


def test_you_are_here_marker_uses_location_and_accuracy():
    # A blue current-position dot with an accuracy ring, distinct from the pin,
    # projected through the same toScreen() helper.
    here = _between("id: hereDot", "// two fingers")
    assert "win.toScreen(Location.lat, Location.lon)" in here
    assert "Location.accuracy" in here
    assert "#1e90ff" in here
    assert "Location.available" in here
