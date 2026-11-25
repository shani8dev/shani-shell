"""Static checks that the render harness cannot PASS a shot that never drew.

dev/render.sh runs inside a container against a live compositor, so these
assert the source carries the actual guard rather than driving it: a post-capture
pixel comparison against the plain desktop, one IPC retry on a blank frame, and
a wait for the previous surface to clear between shots.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = (ROOT / "dev/render.sh").read_text(encoding="utf-8")


def body(name):
    """Source of a shell function declared at render_shell's 4-space indent."""
    lines = SCRIPT.splitlines()
    start = next(i for i, ln in enumerate(lines) if ln.startswith(f"    {name}() {{"))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "    }")
    return "\n".join(lines[start : end + 1])


def test_visual_check_compares_center_to_desktop_baseline():
    b = body("frame_is_blank")
    assert "from PIL import Image" in b  # Pillow, already a dependency
    assert ".resize((W, H))" in b  # downscale before comparing
    assert "int(H * 0.15)" in b and "int(H * 0.85)" in b
    assert "int(W * 0.22)" in b and "int(W * 0.78)" in b  # centre band only
    assert "sys.exit(0 if diff < 12 else 1)" in b  # blank threshold
    assert '"$BASE"' in b
    assert 'BASE="$OUTDIR/01-desktop-rest.png"' in SCRIPT


def test_visual_check_is_opt_in_and_only_for_centered_surfaces():
    b = body("needs_visual")
    assert '[ -n "$2" ] || return 1' in b  # no want → not enforced
    for prefix in (
        "app-*",
        "media-*",
        "clocks-*",
        "quick-look*",
        "settings-*",
        "launcher-*",
        "overview-*",
    ):
        assert prefix in b
    assert "test_render_surfaces.py" in SCRIPT  # mirrors the opt-in visual test


def test_blank_frame_reissues_ipc_and_recaptures_before_failing():
    b = body("shoot")
    assert 'grim "$_path"' in b
    assert b.count('grim "$_path"') == 2  # first shot + recapture
    assert 'frame_is_blank "$_path"' in b
    assert 'ipc_line "$_cmd"' in b  # reissue the opening IPC once
    assert "sleep 1.5" in b
    assert "failed=$((failed+1))" in b
    assert "but no surface drew" in b


def test_both_capture_paths_route_through_shoot_with_expectation():
    for name, cmd in (("capture", '"$cmd"'), ("capture_current", '"$LAST_IPC"')):
        b = body(name)
        assert 'shoot "$name" "$want"' in b
        assert cmd in b


def test_close_all_waits_for_previous_surface_to_clear():
    b = body("close_all")
    assert "ipc_line dismissAll" in b
    assert "waitfor" in b
    for key in (
        "controlCenter",
        "launcher",
        "settingsOpen",
        "chronoaOpen",
        "ring",
        "switcher",
        "layoutSwitcher",
        "expanded",
    ):
        assert key in b
    assert "did not clear" in b
    assert "sleep" in b


def test_catches_lazy_loader_compile_errors_in_qs_log():
    """A LazyLoader compile warning leaves a blank frame with state PASS.

    Quickshell logs ``qs:@/...:line:col: Unexpected token`` (and the other
    compile forms) as WARN, not "QML ERROR". The harness must grep for them
    and fail the run, otherwise a window that never compiled is rendered as a
    plain desktop and reported as success.
    """
    assert "compile_bad=" in SCRIPT
    assert "qs:@" in SCRIPT
    for pattern in (
        "Unexpected token",
        "Cannot assign to non-existent property",
        "is not a type",
    ):
        assert pattern in SCRIPT, f"compile guard missing: {pattern}"
    assert "QML COMPILE ERROR" in SCRIPT
    assert "failed=$((failed+1))" in SCRIPT
