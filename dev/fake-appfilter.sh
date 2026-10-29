#!/bin/sh
# appfilter.py, for the tests: the ids in /tmp/appfilter-blocked (one a line) are blocked
ids=$(sed 's/.*/"&"/' /tmp/appfilter-blocked 2>/dev/null | paste -sd, -)
printf '{"available": true, "blocked": [%s]}\n' "$ids"
exec sleep infinity
