# sourced by dev/shell-test.sh (or: SHANI_ONLINE=1 sh dev/check.sh shell=maps-online)
# ---- Maps against OpenStreetMap's real tiles, Nominatim and OSRM ----
# a few requests, as the services' usage policies allow (one search, one route)
if [ "${SHANI_ONLINE:-}" != 1 ]; then
    result maps-online SKIP "the stand-ins are in use (SHANI_ONLINE=1 for the real services)"
else
    rm -rf /root/.cache/shani-shell/map-tiles
    ipc mapsSearch "Shaniwar Wada, Pune"
    waitfor "abs(d['mapsView'].get('lat', 0) - 18.519) < 0.01 and abs(d['mapsView'].get('lon', 0) - 73.855) < 0.01" 20 \
        && result maps-online-nominatim PASS "$(q "['mapsView']")" || result maps-online-nominatim FAIL "$(q "['mapsView']")"
    sleep 6
    n=$(find /root/.cache/shani-shell/map-tiles -name '*.png' -size +1k 2>/dev/null | wc -l)
    [ "$n" -ge 8 ] && result maps-online-tiles PASS "$n OpenStreetMap tiles" || result maps-online-tiles FAIL "$n tiles"
    shot maps-online-place 0.3
    ipc mapsFrom "Pune Railway Station"
    waitfor "d['mapsView'].get('distance', 0) > 500 and d['mapsView'].get('steps', 0) >= 3 and d['mapsView'].get('route', 0) > 5" 30 \
        && result maps-online-osrm PASS "$(q "['mapsView']['distance']") m, $(q "['mapsView']['steps']") steps" || result maps-online-osrm FAIL "$(q "['mapsView']")"
    sleep 4; shot maps-online-route 0.3
    ipc closeAll
fi
