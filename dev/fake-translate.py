#!/usr/bin/env python3
"""bridge/translate.py's stand-in for the suite: `text` answers TRANSLATED(<input>),
or fails as a missing model would when /tmp/translate-down exists."""
import os, sys
if os.path.exists("/tmp/translate-down"):
    print("translate: the local model did not answer", file=sys.stderr)
    sys.exit(2)
print(f"TRANSLATED({sys.stdin.read().strip()})")
