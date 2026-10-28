#!/usr/bin/env python3
"""Stands in for bridge/bt-agent.py in the dev session: each line written to
/tmp/bt-ask is sent to the shell as a question; the shell's answers are
appended to /tmp/bt-answers."""
import os
import select
import sys
import time

print('{"ready": true}', flush=True)
while True:
    if os.path.exists("/tmp/bt-ask"):
        with open("/tmp/bt-ask") as f:
            sys.stdout.write(f.read())
            sys.stdout.flush()
        os.remove("/tmp/bt-ask")
    r, _, _ = select.select([sys.stdin], [], [], 0.3)
    if r:
        line = sys.stdin.readline()
        if not line:
            break
        with open("/tmp/bt-answers", "a") as f:
            f.write(line)
    time.sleep(0.05)
