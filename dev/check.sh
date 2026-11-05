#!/bin/sh
# The one way in to every test and render. From anywhere, on the host:
#   sh dev/check.sh [--build] [suite...]          (no suite: all)
#
#   unit          pytest: bridges, launch-app, QML patterns   (host python)
#   shell         the whole shell in a nested niri, driven for real
#   idle          just the shell's idle cost (programs, CPU, memory)
#   perf          idle + the budgets: idle frames, memory, open speed, leaks, startup
#   a11y          idle + every surface through AT-SPI, with screenshots
#   greeter       the login screen, the way greetd runs it
#   setup         the first-boot wizard, end to end
#   polkit        the polkit agent, in a systemd-booted container (real logind)
#   admin         shani-admin.py as pkexec runs it            (needs shani-desktop-niri)
#   setup-polkit  first-boot's pkexec rule                    (needs shani-desktop-niri)
#   pam           the lock screen's and greeter's PAM stacks through real libpam (needs shani-desktop-niri)
#   render[=mode] every surface to PNG in out/renders; mode shell|greeter|setup|all
#   showcase      restage the README's two pictures in docs/ (the rest: out/showcase)
#   all           unit shell greeter setup polkit admin setup-polkit pam
#
# --build rebuilds shani-shell-dev first (it is built anyway when missing).
# shani-desktop-niri is looked for beside this repo in shani-pkgbuilds, or at
# $SHANI_DESKTOP_NIRI; shani-testbed (the AT-SPI client) beside this repo.
# Everything a run writes is in out/ (git-ignored, yours to delete): each
# suite's log in out/logs/check-<suite>.log, screenshots in out/shots, renders
# in out/renders; the RESULT lines are counted into out/logs/check-summary.txt and the exit status is non-zero if anything failed.
REPO=$(cd "$(dirname "$0")/.." && pwd)
DESK=${SHANI_DESKTOP_NIRI:-$REPO/../shani-pkgbuilds/shani-desktop-niri}
TESTBED=$REPO/../shani-testbed
IMG=shani-shell-dev
# the containers write as root: hand what they wrote back to you
own() { docker run --rm -v "$REPO":/work $IMG sh -c "mkdir -p /work/out/logs /work/out/shots /work/out/renders && chown -R $(id -u):$(id -g) /work/out/logs /work/out/shots /work/out/renders"; }

build() { docker build -t $IMG -f "$REPO/dev/Containerfile" "$REPO/dev" || exit 1; }
[ "${1:-}" = --build ] && { shift; build; }
docker image inspect $IMG >/dev/null 2>&1 || build
own
[ $# -eq 0 ] && set -- all
[ "$*" = all ] && set -- unit shell greeter setup polkit admin setup-polkit pam

# a dev/ script in a plain container, the repo at /work
box() {
    tb=; [ -d "$TESTBED" ] && tb="-v $(cd "$TESTBED" && pwd):/testbed:ro"
    # shellcheck disable=SC2086
    docker run --rm --cap-add SYS_PTRACE $tb -v "$REPO":/work "$@"
}
run() {
    case "$1" in
        unit) cd "$REPO" && python3 -m pytest tests -q ;;
        shell) box $IMG sh /work/dev/shell-test.sh ;;
        idle|a11y|perf) box -e SHELL_TEST_ONLY="$1" $IMG sh /work/dev/shell-test.sh ;;
        # the greeter's niri config is shani-desktop-niri's, as greetd runs it
        greeter) box -v "$DESK":/desk:ro $IMG sh /work/dev/greeter-test.sh /desk/etc/greetd/shani-niri-greeter.kdl ;;
        setup) box -v "$DESK":/desk:ro $IMG sh /work/dev/setup-test.sh /desk/etc/greetd/shani-niri-greeter.kdl ;;
        pam) box -v "$DESK":/desk:ro $IMG sh /work/dev/pam-test.sh /desk/etc/pam.d/shani-greetd ;;
        polkit) sh "$REPO/dev/polkit-run.sh" ;;
        admin) sh "$REPO/dev/admin-test.sh" "$DESK" ;;
        setup-polkit) sh "$REPO/dev/setup-polkit-test.sh" "$DESK" ;;
        showcase) box $IMG sh /work/dev/showcase.sh ;;
        render|render=*) box $IMG sh /work/dev/render.sh "${1#render=}" ;;
        *) echo "unknown suite: $1 (see the top of dev/check.sh)"; return 2 ;;
    esac
}

summary="$REPO/out/logs/check-summary.txt"; : > "$summary"
bad=0
for s in "$@"; do
    [ "$s" = render ] && s=render=shell
    log="$REPO/out/logs/check-${s%%=*}.log"
    echo "== $s"
    { run "$s"; echo $? > "$log.rc"; } 2>&1 | tee "$log"
    own; rc=$(cat "$log.rc"); rm -f "$log.rc"
    pass=$(grep -c "^RESULT .* PASS" "$log"); fail=$(grep -c "^RESULT .* FAIL" "$log")
    [ "$s" = unit ] && pass=$(grep -oE "[0-9]+ passed" "$log" | grep -oE "[0-9]+" || echo 0) && fail=$(grep -oE "[0-9]+ failed" "$log" | grep -oE "[0-9]+" || echo 0)
    [ "$rc" = 0 ] && [ "${fail:-0}" = 0 ] && v=ok || { v=FAILED; bad=1; }
    printf "%-14s %-7s %4s pass %4s fail   out/logs/%s\n" "$s" "$v" "${pass:-0}" "${fail:-0}" "${log##*/}" >> "$summary"
    grep "^RESULT .* FAIL" "$log" | sed 's/^/                 /' >> "$summary"
done
echo; cat "$summary"
exit $bad
