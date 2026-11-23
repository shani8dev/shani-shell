"""Static checks for the input-service fixes.

The two services that write niri's input include and read the keyboard LEDs.
Each fix gets one test: a bad LED read is not "off", LED paths are re-globed
after hotplug, `known` reflects a real read, repeat values are clamped before
they reach niri, and keyboard-layout ids cannot break the generated KDL.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def input_cfg():
    return (ROOT / "shani/Services/InputConfig.qml").read_text(encoding="utf-8")


def lock_keys():
    return (ROOT / "shani/Services/LockKeys.qml").read_text(encoding="utf-8")


def test_failed_led_read_is_not_reported_as_off():
    s = lock_keys()
    body = s.split("function readLed", 1)[1].split("\n    }", 1)[0]
    assert "file.reload()" in body
    assert "parseInt(file.text(), 10)" in body
    assert "isNaN(v) || (v !== 0 && v !== 1)" in body
    # the early return must come before the state assignment
    assert body.index("return false") < body.index("root[key] = v > 0")
    assert "return true" in body


def test_led_paths_are_rediscovered_after_hotplug_or_resume():
    s = lock_keys()
    assert "id: discover" in s
    assert "interval: 5000" in s
    # Quickshell Process has no restart() — stop/start is the supported way
    assert "discover.running = false; discover.running = true" in s
    # re-globbing is slow; the actual LED polling stays at 500 ms
    assert "interval: 500\n" in s


def test_known_is_only_set_after_a_successful_read():
    s = lock_keys()
    assert 'const capsOk = root.readLed(capsFile, root.capsPath, "caps")' in s
    assert 'const numOk = root.readLed(numFile, root.numPath, "num")' in s
    assert "if (capsOk || numOk) root.known = true" in s


def test_layout_ids_are_filtered_before_writing_kdl():
    s = input_cfg()
    assert "function kbLayouts()" in s
    match = re.search(r"function kbLayouts\(\).*?/(.+?)/\.test", s, re.S)
    assert match, "no layout-id filter regex in kbLayouts()"
    rx = re.compile(match.group(1))
    for good in ("us", "in", "de+neo", "us+intl-2", "ru_TT", "epo"):
        assert rx.match(good), good
    for bad in ('us" } spawn "evil', "us,in", "us\nsomething", "; spawn", ""):
        assert not rx.match(bad), bad
    lines = [
        l
        for l in s.splitlines()
        if '            layout \\"' in l or '            variant \\"' in l
    ]
    assert len(lines) == 2
    assert all("root.kbLayouts()" in l for l in lines)
    assert all("Array.from(d.kbLayouts)" not in l for l in lines)


def test_repeat_delay_and_rate_are_clamped_before_writing_kdl():
    s = input_cfg()
    body = s.split("function boundedInt", 1)[1].split("\n    }", 1)[0]
    assert "Math.round(Number(v))" in body
    assert "isFinite(n)" in body
    assert "Math.min(hi, Math.max(lo, n))" in body
    for field, low, high in (("keyRepeatDelay", 0, 10000), ("keyRepeatRate", 0, 1000)):
        match = re.search(
            r"repeat-(?:delay|rate) \" \+ root\.boundedInt\(d\."
            + field
            + r", (\d+), (\d+)\)",
            s,
        )
        assert match, field
        assert (int(match.group(1)), int(match.group(2))) == (low, high)
