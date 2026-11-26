#!/bin/sh
# The one way in to every test and render. From anywhere, on the host:
#   sh dev/check.sh [--build] [suite...]          (no suite: all)
#
#   unit          pytest: bridges, launch-app, QML patterns   (host python)
#   shell         the whole shell in a nested niri, driven for real
#   shell=<part>  just dev/shell-parts/<part>.sh (one feature), on a fresh session
#   idle          just the shell's idle cost (programs, CPU, memory)
#   perf          idle + the budgets: idle frames, memory, open speed, leaks, startup
#   a11y          idle + every surface through AT-SPI, with screenshots
#   greeter       the login screen, the way greetd runs it
#   setup         the first-boot wizard, end to end
#   polkit        the polkit agent, in a systemd-booted container (real logind)
#   admin         shani-admin.py as pkexec runs it            (needs shani-desktop-niri)
#   setup-polkit  first-boot's pkexec rule                    (needs shani-desktop-niri)
#   pam           the lock screen's and greeter's PAM stacks through real libpam (needs shani-desktop-niri)
#   keyring       a real sign-in unlocks the keyring (oo7), systemd-booted container (needs shani-desktop-niri)
#   surfaces      every surface shell.qml loads has a capture (dev/surfaces.tsv)
#   render[=mode] every surface to PNG in out/renders; mode shell|greeter|setup|all
#   render=matrix[:kinds] the key surfaces on all 8 form factors (or only kinds, comma-separated), each in its own layout (and all 14 layouts on a
#                 computer), each at its own screen shape: out/renders/matrix/<kind>
#                 (SHANI_FORM_FACTOR=tv sh dev/check.sh render: drawn as on a TV)
#   showcase      restage the README's two pictures in docs/ (the rest: out/showcase)
#   demo[=a,b]    record the README's GIFs into out/demos (CHRONOA=real for the AI scenes)
#   montage       join out/demos' clips into out/demos/tour.mp4 (LinkedIn, the blog)
#   all           unit surfaces shell greeter setup polkit admin setup-polkit pam keyring
#
# --build rebuilds shani-shell-dev first (it is built anyway when missing).
# SHANI_ONLINE=1 sh dev/check.sh shell=maps-online: Maps against OpenStreetMap's real
# tiles, Nominatim and OSRM (the suite uses dev/fake-osm.py: same answers every run).
# CHRONOA=real sh dev/check.sh shell=<part>: the real shani-chronoa (../shani-chronoa)
# instead of dev/mock-chronoa.py, answering with the model on this machine's
# 127.0.0.1:8765 (the container joins the host network). The full suite keeps
# the mock: the same answers every run.
# shani-desktop-niri is looked for beside this repo in shani-pkgbuilds, or at
# $SHANI_DESKTOP_NIRI; shani-testbed (the AT-SPI client) beside this repo.
# Everything a run writes is in out/ (git-ignored, yours to delete): each
# suite's log in out/logs/check-<suite>.log, screenshots in out/shots, renders
# in out/renders; the RESULT lines are counted into out/logs/check-summary.txt and the exit status is non-zero if anything failed.
REPO=$(cd "$(dirname "$0")/.." && pwd)
DESK=${SHANI_DESKTOP_NIRI:-$REPO/../shani-pkgbuilds/shani-desktop-niri}
TESTBED=$REPO/../shani-testbed
IMG=shani-shell-dev
# the containers write as root: hand what they wrote back to you. Under rootless
# podman that root is a subuid on the host (uid 100999 here), so the chown has to
# be made from inside its user namespace - asking the container to chown to
# `id -u` hands the files to a subuid instead, and out/ stays unwritable (which
# killed a render run before its first frame). A real docker writes as real root:
# then only root can give it back, and the container does it.
own() {
    if podman unshare true 2>/dev/null; then
        # a fresh checkout has no out/ yet: the summary is written here before any box runs
        mkdir -p "$REPO/out/logs" "$REPO/out/shots" "$REPO/out/renders"
        podman unshare chown -R 0:0 "$REPO/out" 2>/dev/null || true
    else
        docker run --rm -v "$REPO":/work $IMG sh -c "mkdir -p /work/out/logs /work/out/shots /work/out/renders && chown -R $(id -u):$(id -g) /work/out/logs /work/out/shots /work/out/renders" 2>/dev/null || true
    fi
}


build() { docker build -t $IMG -f "$REPO/dev/Containerfile" "$REPO/dev" || exit 1; }
[ "${1:-}" = --build ] && { shift; build; }
docker image inspect $IMG >/dev/null 2>&1 || build
own
# every suite writes into the same out/shots; clear it once per invocation so
# a review cannot mistake last week's screenshots for this run's
rm -f "$REPO"/out/shots/*.png
[ $# -eq 0 ] && set -- all
[ "$*" = all ] && set -- unit surfaces shell greeter setup polkit admin setup-polkit pam keyring

# a dev/ script in a plain container, the repo at /work
box() {
    tb=; [ -d "$TESTBED" ] && tb="-v $(cd "$TESTBED" && pwd):/testbed:ro"
    # shellcheck disable=SC2086
    # IPC_LOCK: the keyring daemon locks its memory (secrets never reach swap) or will not start
    # CHRONOA=real: the real shani-chronoa from beside this repo, on the host
    # network for the model on 127.0.0.1:8765. Phone backends ship in this tree.
    ch=; [ "${CHRONOA:-}" = real ] && ch="-e CHRONOA=real --network=host -v $(cd "$REPO/../shani-chronoa" && pwd):/chronoa:ro"
    # SHANI_ONLINE=1: the real web services where the suite has stand-ins (Maps)
    on=; [ "${SHANI_ONLINE:-}" = 1 ] && on="-e SHANI_ONLINE=1"
    # SHANI_FORM_FACTOR=tv|handheld|tablet|board|phone|laptop: every screen is that
    # kind (docs/FORM-FACTORS.md) - the suites and renders at its size
    ff=; [ -n "${SHANI_FORM_FACTOR:-}" ] && ff="-e SHANI_FORM_FACTOR=$SHANI_FORM_FACTOR"
    # SHANI_WIDTH / SHANI_SCREEN: the shape of the nested niri, so a phone can
    # be a phone rather than a small window (dev/session.sh)
    shape=; [ -n "${SHANI_WIDTH:-}" ] && shape="$shape -e SHANI_WIDTH=$SHANI_WIDTH"
    shape="$shape -e SHANI_SCREEN=${SHANI_SCREEN:-1080}"
    # SHANI_APPS: the apps the apps / apps-phone parts open (all when unset)
    [ -n "${SHANI_APPS:-}" ] && shape="$shape -e SHANI_APPS=$(printf %s "$SHANI_APPS" | tr " " ,)"
    # SHANI_CHECK_MEMORY: a ceiling for the container. A shell that grows without
    # end (a layout loop once took qs to 12 GB) is killed inside its own box
    # instead of sending the host's OOM killer after the person's desktop.
    mem="--memory=${SHANI_CHECK_MEMORY:-6g} --memory-swap=${SHANI_CHECK_MEMORY:-6g}"
    # PYTHONDONTWRITEBYTECODE: no root-owned __pycache__ left in the checkout
    # (only sudo could remove a worktree the box had run in)
    docker run --rm --cap-add SYS_PTRACE --cap-add IPC_LOCK -e PYTHONDONTWRITEBYTECODE=1 $mem $tb $ch $on $ff $shape -v "$REPO":/work "$@"
}
run() {
    case "$1" in
        unit) cd "$REPO" && python3 -m pytest tests -q ;;
        # shani-desktop-niri at /desk: its foot.ini, as the image installs it (dev/session.sh)
        shell) box -v "$DESK":/desk:ro $IMG sh /work/dev/shell-test.sh ;;
        # one part of it on a fresh session: dev/shell-parts/<name>.sh
        shell=*) box -v "$DESK":/desk:ro -e SHELL_TEST_ONLY="part:${1#shell=}" $IMG sh /work/dev/shell-test.sh ;;
        idle|a11y|perf) box -v "$DESK":/desk:ro -e SHELL_TEST_ONLY="$1" $IMG sh /work/dev/shell-test.sh ;;
        # the greeter's niri config is shani-desktop-niri's, as greetd runs it
        greeter) box -v "$DESK":/desk:ro $IMG sh /work/dev/greeter-test.sh /desk/etc/greetd/shani-niri-greeter.kdl ;;
        setup) box -v "$DESK":/desk:ro $IMG sh /work/dev/setup-test.sh /desk/etc/greetd/shani-niri-greeter.kdl ;;
        pam) box -v "$DESK":/desk:ro $IMG sh /work/dev/pam-test.sh /desk/etc/pam.d/shani-greetd ;;
        polkit) sh "$REPO/dev/polkit-run.sh" ;;
        keyring) sh "$REPO/dev/keyring-run.sh" "$DESK" ;;
        admin) sh "$REPO/dev/admin-test.sh" "$DESK" ;;
        setup-polkit) sh "$REPO/dev/setup-polkit-test.sh" "$DESK" ;;
        showcase) box -v "$DESK":/desk:ro $IMG sh /work/dev/showcase.sh ;;
        # the README's GIFs, out/demos/<scene>.gif (demo=island,ring: just those)
        demo|demo=*) sc=; [ "$1" != demo ] && sc=$(echo "${1#demo=}" | tr , " ")
                     box -v "$DESK":/desk:ro $IMG sh /work/dev/demo.sh $sc ;;
        # the clips joined into one MP4 (out/demos/tour.mp4), for where a GIF does not play
        montage) box $IMG sh /work/dev/montage.sh ;;
        # every surface shell.qml loads vs every capture any harness takes
        # (dev/surfaces.tsv); host python, no container: RESULT per problem
        surfaces) python3 "$REPO/tools/surfaces.py" check | sed -E 's/^([0-9]+ surfaces, 0 problem.*)$/RESULT surfaces-covered PASS (\1)/; t; s/^([0-9]+ surfaces, .*)$/RESULT surfaces-covered FAIL (\1)/; t; s/^/  /' ;;
        # key surfaces on every kind of screen, each in its own session at its
        # shape, plus every desktop layout on the computer: out/renders/matrix/<kind>
        # render=matrix:phone,board - only those kinds
        render=matrix|render=matrix:*)
            rc=0; only=","${1#render=matrix:}","; [ "$1" = render=matrix ] && only=""
            for spec in computer:1920x1080 laptop:1920x1080 tablet:1280x800 handheld:1280x800 phone:412x915 tv:1920x1080 board:1920x1080 projector:1920x1080; do
                kind=${spec%%:*}; wh=${spec#*:}
                [ -z "$only" ] || case "$only" in *",$kind,"*) ;; *) continue ;; esac
                echo "== form factor $kind ($wh)"
                ( SHANI_FORM_FACTOR=$kind SHANI_WIDTH=${wh%x*} SHANI_SCREEN=${wh#*x}
                  box $IMG sh /work/dev/render.sh matrix ) || rc=1
            done
            return $rc ;;
        render|render=*)
            mode=${1#render=}
            case "$mode" in
                ""|shell|greeter|setup|all) ;;
                *) echo "unknown render mode: $mode (shell|greeter|setup|all|matrix)"; return 2 ;;
            esac
            box $IMG sh /work/dev/render.sh "$mode" ;;
        *) echo "unknown suite: $1 (see the top of dev/check.sh)"; return 2 ;;
    esac
}

summary="$REPO/out/logs/check-summary.txt"; : > "$summary"
bad=0
for s in "$@"; do
    [ "$s" = render ] && s=render=shell
    name=${s%%=*}; case "$s" in shell=*) name="shell-${s#shell=}" ;; esac
    log="$REPO/out/logs/check-$name.log"
    echo "== $s"
    { run "$s"; echo $? > "$log.rc"; } 2>&1 | tee "$log"
    own; rc=$(cat "$log.rc"); rm -f "$log.rc"
    pass=$(grep -c "^RESULT .* PASS" "$log"); fail=$(grep -c "^RESULT .* FAIL" "$log")
    [ "$s" = unit ] && pass=$(grep -oE "[0-9]+ passed" "$log" | grep -oE "[0-9]+" || echo 0) && fail=$(grep -oE "[0-9]+ failed" "$log" | grep -oE "[0-9]+" || echo 0)
    # A shell suite that ran no checks is not a pass: a typo in `shell=<part>`
    # used to source nothing, print unrelated PASS lines and come back green.
    # Render modes write pictures instead of RESULT lines, so they need no PASS.
    need_pass=1; case "$s" in render*) need_pass=0 ;; esac
    if [ "$rc" = 0 ] && [ "${fail:-0}" = 0 ] && { [ "$need_pass" = 0 ] || [ "${pass:-0}" -gt 0 ]; }; then
        v=ok
    else
        v=FAILED; bad=1
        [ "${pass:-0}" = 0 ] && echo "                 no checks ran (wrong suite name?)" >> "$summary"
    fi
    printf "%-14s %-7s %4s pass %4s fail   out/logs/%s\n" "$s" "$v" "${pass:-0}" "${fail:-0}" "${log##*/}" >> "$summary"
    grep "^RESULT .* FAIL" "$log" | sed 's/^/                 /' >> "$summary"
done
echo; cat "$summary"
exit $bad
