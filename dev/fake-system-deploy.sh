#!/bin/sh
# Harness stand-in for `shani-deploy`: reads and verification go to the boot
# tools' stand-in; the maintenance bridge's write verbs keep the older root
# stand-in. Each keeps its own call log, so a check can see which was reached.
case "$*" in
    *--cleanup*|*--optimize*|*--rollback*|*--set-channel*|*--install*)
        exec /work/dev/fake-system-root.py "$@" ;;
    *)
        # a symlink: the stand-in reads its own basename to pick the tool
        exec /tmp/fake-system/bin-boot/shani-deploy "$@" ;;
esac
