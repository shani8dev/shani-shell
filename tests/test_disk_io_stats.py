"""Disk I/O rates and root/home capacity in the System Monitor.

The QML parses /proc itself (there is no Python/QML bridge for it), so these
tests pin the exact device regex and field indices the QML uses and replay them
in Python against real-shaped diskstats/df output. That is what catches the two
costly mistakes here: counting a partition and its whole disk twice, and
dividing sectors by a fixed interval instead of the sampled timestamps.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SYS = "shani/Services/SysStats.qml"
PROC = "shani/Modules/Processes/Processes.qml"
DESK = "shani/Modules/Background/DesktopWidgets.qml"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def stats_line(name, major, minor, read_sectors, write_sectors):
    """One /proc/diskstats line; fields 5 and 9 are the sector counters."""
    fields = [
        major,
        minor,
        name,
        100,
        0,
        read_sectors,
        10,
        50,
        0,
        write_sectors,
        20,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    return "  ".join(str(x) for x in fields)


# whole devices and their partitions, plus the virtual devices that must not
# be counted; the partition counters are deliberately huge so double-counting
# cannot pass by accident
DISKSTATS = "\n".join(
    [
        stats_line("sda", 8, 0, 100, 200),
        stats_line("sda1", 8, 1, 9999, 9999),
        stats_line("nvme0n1", 259, 0, 300, 400),
        stats_line("nvme0n1p1", 259, 1, 8888, 8888),
        stats_line("vda", 252, 0, 500, 600),
        stats_line("vda1", 252, 1, 7777, 7777),
        stats_line("mmcblk0", 179, 0, 700, 800),
        stats_line("mmcblk0p1", 179, 1, 6666, 6666),
        stats_line("loop0", 7, 0, 5555, 5555),
        stats_line("ram0", 1, 0, 4444, 4444),
        stats_line("dm-0", 253, 0, 3333, 3333),
        stats_line("sr0", 11, 0, 2222, 2222),
    ]
)


def qml_disk_regex():
    m = re.search(r'diskDevicePattern:\s*"([^"]+)"', read(SYS))
    assert m, "SysStats must expose the device regex used by its parser"
    return re.compile(m.group(1))


def parse_sectors(text):
    """The QML algorithm, in Python, using the regex taken from the QML file."""
    rx = qml_disk_regex()
    read_total = write_total = 0
    for line in text.split("\n"):
        f = line.split()
        if len(f) < 10 or not rx.fullmatch(f[2]):
            continue
        read_total += int(f[5])  # sectors read
        write_total += int(f[9])  # sectors written
    return read_total, write_total


def parse_capacity(text):
    """Mirror of SysStats.parseCapacity over `df --output=target,size,used,avail`."""
    lines = [l for l in text.strip().split("\n") if l.strip()]
    if len(lines) < 2:
        return None
    r = lines[1].split()
    h = lines[2].split() if len(lines) > 2 else r
    if len(r) < 4 or len(h) < 4:
        return None
    return (
        int(r[1]),
        int(r[2]),
        int(h[1]),
        int(h[2]),
        r[1] == h[1] and r[2] == h[2] and r[3] == h[3],
    )


# ---- the parser's convention ----------------------------------------------


def test_only_whole_disks_are_counted():
    rx = qml_disk_regex()
    for name in ("sda", "sdb", "nvme0n1", "nvme1n2", "vda", "mmcblk0"):
        assert rx.fullmatch(name), name
    for name in (
        "sda1",
        "nvme0n1p1",
        "vda1",
        "mmcblk0p1",
        "loop0",
        "ram0",
        "dm-0",
        "md0",
        "sr0",
        "zram0",
    ):
        assert not rx.fullmatch(name), name


def test_sector_math_skips_partitions_and_virtual_devices():
    # 100+300+500+700 = 1600 read, 200+400+600+800 = 2000 written
    assert parse_sectors(DISKSTATS) == (1600, 2000)


def test_rate_uses_sector_bytes_over_the_measured_delta():
    read_sectors, write_sectors = parse_sectors(DISKSTATS)
    dt = 3.0
    assert read_sectors * 512 / dt == 1600 * 512 / 3.0
    assert write_sectors * 512 / dt == 2000 * 512 / 3.0


def test_qml_uses_those_indices_and_a_timestamp_delta():
    q = read(SYS)
    assert "read += Number(f[5]) || 0" in q
    assert "write += Number(f[9]) || 0" in q
    assert "f.length < 10" in q
    assert "(cur.read - root.lastDisk.read) * 512 / dt" in q
    assert "(cur.write - root.lastDisk.write) * 512 / dt" in q
    assert "(now - root.lastDisk.t) / 1000" in q
    # no 500 ms poll and no division by a constant interval
    assert "interval: 500" not in q
    assert "/ root.interval" not in q
    assert "Math.max(0," in q


# ---- idle cost / gating ----------------------------------------------------


def test_diskstats_reload_is_only_in_the_existing_sampling_timer():
    q = read(SYS)
    assert "readonly property int interval: 3000" in q
    assert q.count("diskStats.reload()") == 1
    assert 'path: "/proc/diskstats"' in q
    timer = q[
        q.index("interval: root.interval") : q.index("FileView {\n        id: stat")
    ]
    assert "running: root.wanted" in timer
    assert "diskStats.reload()" in timer


def test_capacity_read_is_slow_and_gated_by_wanted():
    q = read(SYS)
    timer = q[
        q.index("id: capacityTick") - 7 : q.index("Process {\n        id: dfProc")
    ]
    assert "interval: 60000" in timer
    assert "running: root.wanted" in timer
    assert "triggeredOnStart: true" in timer
    assert "dfProc.running = true" in timer
    assert q.count("dfProc.running = true") == 1
    proc = q[q.index("id: dfProc") : q.index("FileView {\n        id: uptimeView")]
    assert '"df", "-B1", "--output=target,size,used,avail", "/", "/home"' in proc
    assert "onStreamFinished: root.parseCapacity(text)" in proc


def test_rates_reset_when_nobody_wants_stats():
    q = read(SYS)
    handler = q[
        q.index("onWantedChanged:") : q.index(
            "Timer {\n        interval: root.interval"
        )
    ]
    assert "if (!wanted)" in handler
    assert (
        "root.lastDisk = null; root.diskReadRate = 0; root.diskWriteRate = 0;"
        in handler
    )


def test_capacity_parser_detects_a_shared_home_filesystem():
    shared = (
        "Mounted on    1B-blocks         Used      Avail\n"
        "/          499680116736 465407885312  8814694400\n"
        "/          499680116736 465407885312  8814694400\n"
    )
    separate = (
        "Mounted on    1B-blocks         Used      Avail\n"
        "/          499680116736 465407885312  8814694400\n"
        "/home      100000000000  20000000000  80000000000\n"
    )
    assert parse_capacity(shared)[4] is True
    assert parse_capacity(separate)[4] is False
    assert parse_capacity(separate)[:4] == (
        499680116736,
        465407885312,
        100000000000,
        20000000000,
    )
    q = read(SYS)
    assert "lines.length > 2 ? lines[2]" in q
    assert "r[1] === h[1] && r[2] === h[2] && r[3] === h[3]" in q


# ---- surfaces --------------------------------------------------------------


def test_processes_shows_rates_and_capacity_with_severity_tint():
    q = read(PROC)
    assert 'Tr.t("Disk I/O")' in q
    assert "SysStats.rate(SysStats.diskReadRate)" in q
    assert "SysStats.rate(SysStats.diskWriteRate)" in q
    assert "SysStats.rootUsed" in q and "SysStats.rootTotal" in q
    assert "SysStats.homeUsed" in q and "SysStats.homeTotal" in q
    assert "used / total > 0.9 ? Theme.amber" in q
    assert "!SysStats.homeSameDevice" in q


def test_desktop_widget_extends_the_tints_model_without_dropping_others():
    q = read(DESK)
    # the tints model another agent added must still be intact
    assert "SysStats.cpu > 0.85 ? Theme.amber" in q
    assert "SysStats.mem > 0.9 ? Theme.amber" in q
    assert '{ label: "disk", value: statsCard.rootUsedPct,' in q
    assert "statsCard.rootUsedPct > 0.9 ? Theme.amber" in q
