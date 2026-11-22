#!/bin/sh
# mediainfo's stand-in for the suite: JSON for the one clip the player opens.
# Real mediainfo takes --Output=JSON FILE; the fake answers for anything.
cat <<'JSON'
{"media":{"track":[
 {"@type":"General","Format":"WebM","Duration":8.0,"FileSize":262579},
 {"@type":"Video","Format":"VP9","Width":640,"Height":360,"BitRate":240000,"FrameRate":25.0},
 {"@type":"Audio","Format":"Vorbis","BitRate":64000,"Channels":2}
]}}
JSON