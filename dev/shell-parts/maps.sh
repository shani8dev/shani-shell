# sourced by dev/shell-test.sh (or alone: sh dev/check.sh shell=maps)
# ---- Maps: search, a map that fills the window, pan and zoom, directions ----
# offline: dev/fake-osm.py stands in for OpenStreetMap's tiles, Nominatim and OSRM
ipc mapsSearch "Shaniwar Wada"
waitfor "abs(d['mapsView'].get('lat', 0) - 18.5195) < 0.001" 8 && result maps-search-finds-place PASS || result maps-search-finds-place FAIL "$(q "['mapsView']")"
sleep 2
n=$(find /root/.cache/shani-shell/map-tiles -name '*.png' 2>/dev/null | wc -l)
[ "$n" -ge 12 ] && result maps-tiles-fill-the-view PASS "$n tiles" || result maps-tiles-fill-the-view FAIL "$n tiles"
# what is drawn, not only what is on disk: a search's tiles appear without anything
# else moving the map, and every slot shows its own tile - maximised too (slots kept
# a neighbour's picture once, and the same streets showed twice)
drawn() { q "['mapsView'].get('tilesDrawn', 0), d['mapsView'].get('tilesDistinct', 0)"; }
waitfor "d['mapsView'].get('tilesDrawn', 0) >= 12 and d['mapsView']['tilesDrawn'] == d['mapsView']['tilesDistinct']" 10 \
    && result maps-search-draws-its-tiles PASS "$(drawn)" || result maps-search-draws-its-tiles FAIL "drawn, distinct: $(drawn)"
niri msg action maximize-column; sleep 1
waitfor "d['mapsView'].get('tilesDrawn', 0) >= 20 and d['mapsView']['tilesDrawn'] == d['mapsView']['tilesDistinct']" 10 \
    && result maps-maximised-no-tile-twice PASS "$(drawn)" || result maps-maximised-no-tile-twice FAIL "drawn, distinct: $(drawn)"
niri msg action maximize-column; sleep 1
shot maps-place 0.3
lon0=$(q "['mapsView']['lon']")
ipc mapsPan "512,0"; sleep 0.6
python3 -c "import sys; sys.exit(0 if float('$(q "['mapsView']['lon']")') > float('$lon0') else 1)" && result maps-drag-pans PASS || result maps-drag-pans FAIL "lon $lon0 -> $(q "['mapsView']['lon']")"
z0=$(q "['mapsView']['zoom']"); ipc mapsZoomBy -2; sleep 0.4
[ "$(q "['mapsView']['zoom']")" = "$((z0 - 2))" ] && result maps-zoom PASS || result maps-zoom FAIL "$z0 -> $(q "['mapsView']['zoom']")"
# directions: no location in the container, so from a typed start
ipc mapsFrom "Pune Station"
waitfor "d['mapsView'].get('distance') == 2450 and d['mapsView'].get('steps') == 3 and d['mapsView'].get('route') == 3" 10 \
    && result maps-directions PASS || result maps-directions FAIL "$(q "['mapsView']")"
sleep 0.8; shot maps-route 0.3
ipc closeAll
