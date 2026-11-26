"""The shell's read-only inventory op, end to end on a private bus.

A fixture Chronoa agent owns the real Agent interface; the real bridge answers
the shell's socket requests; a socket client checks every section's shape and
words. The engine-off case runs the same bridge with no Agent on the bus. The
systemctl stand-in is exercised through its SHANI_* override as well.
"""

from __future__ import annotations

import importlib.util
import json
import os
import queue
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

gi = pytest.importorskip("gi")
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bridge"
AGENT = ROOT / "dev/fake-chronoa-agent.py"
SYSTEMCTL = ROOT / "dev/fake-chronoa-systemctl.py"
UNIT = "shani-chronoa-engine.service"

SECTIONS = (
    "conversations",
    "models",
    "skills",
    "routines",
    "triggers",
    "privacy",
    "memory",
    "senses",
    "capabilities",
    "status",
)

# Distinctive fixture words a shell screenshot can also look for.
LIST_WORDS = {
    "conversations": {"title": "Trip planning"},
    "models": {"task": "chat", "model": "local-test-model"},
    "skills": {"name": "check_weather"},
    "routines": {"name": "Good morning"},
    "triggers": {"name": "Low battery"},
    "memory": {"content": "Prefers trains to flights"},
    "senses": {"key": "senses.screen.read", "enabled": True},
    "capabilities": {"label": "Check the weather", "tool": "check_weather"},
}
DICT_WORDS = {
    "privacy": ("granted_consent_key", "senses.screen.read"),
    "status": ("llm_model", "local-test-model"),
}

FIELDS = {
    "conversations": {
        "id",
        "title",
        "updated",
        "created",
        "messages",
        "active",
        "forked_from",
    },
    "models": {"task", "model", "why"},
    "skills": {"name", "description", "gate"},
    "routines": {"name", "phrases"},
    "triggers": {
        "name",
        "sense",
        "match_mode",
        "substring",
        "keywords",
        "actuator",
        "arguments",
        "cooldown_seconds",
        "enabled",
        "allow_destructive",
        "last_fired_at",
    },
    "memory": {"content", "source", "created_at", "metadata"},
    "senses": {"name", "key", "enabled"},
    "capabilities": {"tool", "group", "label", "description", "consent_key", "example"},
}


@pytest.fixture
def bus():
    if not shutil.which("dbus-daemon"):
        pytest.skip("no dbus-daemon")
    daemon = subprocess.Popen(
        ["dbus-daemon", "--session", "--nofork", "--print-address=1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    try:
        address = daemon.stdout.readline().strip()
        if not address:
            pytest.skip("dbus-daemon gave no address")
        yield address
    finally:
        daemon.terminate()
        try:
            daemon.wait(timeout=5)
        except subprocess.TimeoutExpired:
            daemon.kill()
            daemon.wait()


def bus_has_owner(address: str, name: str) -> bool:
    conn = Gio.DBusConnection.new_for_address_sync(
        address,
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
        | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None,
        None,
    )
    try:
        reply = conn.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            GLib.Variant("(s)", (name,)),
            None,
            Gio.DBusCallFlags.NONE,
            1000,
            None,
        )
        return bool(reply.unpack()[0])
    finally:
        conn.close()


def wait_for(check, timeout=5.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if check():
            return True
        time.sleep(0.02)
    return False


class Client:
    """The shell side of the bridge socket: one JSON request, one broadcast."""

    def __init__(self, path: Path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(str(path))
        self.q: queue.Queue = queue.Queue()
        self.seen: list[dict] = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        with self.sock.makefile("r", encoding="utf-8") as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                self.seen.append(obj)
                self.q.put(obj)

    def send(self, **msg):
        self.sock.sendall((json.dumps(msg) + "\n").encode())

    def wait(self, kind: str, req_id: str, timeout=6.0) -> dict:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                obj = self.q.get(timeout=max(0.05, end - time.monotonic()))
            except queue.Empty:
                break
            if obj.get("type") == kind and obj.get("id") == req_id:
                return obj
        raise AssertionError(f"no {kind} for {req_id}: {self.seen[-5:]}")

    def close(self):
        self.sock.close()


def start_agent(tmp_path: Path, address: str) -> subprocess.Popen:
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=address, HOME=str(tmp_path))
    proc = subprocess.Popen(
        [sys.executable, str(AGENT)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert wait_for(lambda: bus_has_owner(address, "dev.shani.chronoa.Agent")), (
        "fake Agent did not take its bus name",
        proc.stderr.read() if proc.poll() else "",
    )
    return proc


def start_bridge(tmp_path: Path, address: str) -> tuple[subprocess.Popen, Client]:
    sock = tmp_path / "chronoa.sock"
    runtime = tmp_path / "runtime"
    runtime.mkdir(exist_ok=True)
    env = dict(
        os.environ,
        DBUS_SESSION_BUS_ADDRESS=address,
        SHANI_CHRONOA_SOCK=str(sock),
        HOME=str(tmp_path),
        XDG_CONFIG_HOME=str(tmp_path / "config"),
        XDG_DATA_HOME=str(tmp_path / "data"),
        XDG_STATE_HOME=str(tmp_path / "state"),
        XDG_RUNTIME_DIR=str(runtime),
    )
    proc = subprocess.Popen(
        [sys.executable, str(BRIDGE / "chronoa-bridge.py")],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        assert wait_for(lambda: sock.exists()), (
            "bridge did not open its socket",
            proc.stderr.read() if proc.poll() else "",
        )
        assert wait_for(lambda: proc.poll() is None or os.path.exists(sock))
        return proc, Client(sock)
    except Exception:
        proc.terminate()
        proc.wait(timeout=5)
        raise


def stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def check_section(section: str, items) -> None:
    if section in DICT_WORDS:
        key, value = DICT_WORDS[section]
        assert isinstance(items, dict) and items[key] == value, (section, items)
        return
    assert isinstance(items, list) and items, (section, items)
    assert all(FIELDS[section] <= set(item) for item in items), (section, items)
    wanted = LIST_WORDS[section]
    assert any(all(item.get(k) == v for k, v in wanted.items()) for item in items), (
        section,
        items,
    )


def test_all_sections_over_the_socket_with_the_agent_running(bus, tmp_path):
    agent = start_agent(tmp_path, bus)
    bridge, client = start_bridge(tmp_path, bus)
    try:
        for i, section in enumerate(SECTIONS):
            req_id = f"inv-{i}"
            client.send(op="inventory", id=req_id, section=section, limit=3)
            reply = client.wait("inventory", req_id)
            assert reply["section"] == section, reply
            assert "error" not in reply, reply
            check_section(section, reply["items"])
    finally:
        client.close()
        stop(bridge)
        stop(agent)


def test_unknown_section_is_a_refusal_with_the_allowed_names(bus, tmp_path):
    agent = start_agent(tmp_path, bus)
    bridge, client = start_bridge(tmp_path, bus)
    try:
        client.send(op="inventory", id="bad", section="not-a-section")
        reply = client.wait("inventory", "bad")
        assert reply["error"] == "unknown section", reply
        assert reply["items"] == []
        assert set(reply["allowed"]) == set(SECTIONS)
    finally:
        client.close()
        stop(bridge)
        stop(agent)


def test_no_agent_gives_a_plain_error(bus, tmp_path):
    bridge, client = start_bridge(tmp_path, bus)
    try:
        assert not bus_has_owner(bus, "dev.shani.chronoa.Agent")
        client.send(op="inventory", id="off", section="models")
        reply = client.wait("inventory", "off")
        assert reply == {
            "type": "inventory",
            "id": "off",
            "section": "models",
            "error": "Chronoa is not running",
            "items": [],
        }
    finally:
        client.close()
        stop(bridge)


def test_the_bridge_never_accepts_an_unbounded_limit():
    spec = importlib.util.spec_from_file_location(
        "chronoa_bridge_test", BRIDGE / "chronoa-bridge.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(BRIDGE))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.pop(0)
    assert module.inventory_limit(None) == 100
    assert module.inventory_limit("nonsense") == 100
    assert module.inventory_limit(100000) == 100
    assert module.inventory_limit(0) == 1
    assert module.inventory_limit(-8) == 1
    assert module.inventory_limit(7) == 7


def test_service_switch_is_a_fixed_user_unit_argv():
    engine = (ROOT / "shani/Services/ChronoaEngine.qml").read_text()
    assert '"systemctl"' in engine
    assert 'root.tool, "--user"' in engine
    assert 'readonly property string unit: "shani-chronoa-engine.service"' in engine
    for bad in ("pkexec", "sudo", "gapplication", "sh -c"):
        assert bad not in engine, bad

    index = (ROOT / "shani/Modules/Settings/SettingsIndex.js").read_text()
    for section in SECTIONS:
        assert 'page: "' + section + '"' in index, section
    page = (ROOT / "shani/Modules/Settings/SettingsPage.qml").read_text()
    assert 'entry.cat === "chronoa" && entry.page' in page


def test_systemctl_standin_only_touches_the_engine_unit(tmp_path):
    log = tmp_path / "calls" / "calls"
    env = dict(os.environ, SHANI_CHRONOA_SYSTEMCTL_LOG=str(log))

    def run(*args):
        return subprocess.run(
            [sys.executable, str(SYSTEMCTL), *args],
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
        )

    def state(*args):
        out = run(*args)
        assert out.returncode == 0, out.stderr
        return out.stdout.strip()

    assert state("--user", "show", "-p", "ActiveState", "--value", UNIT) == "inactive"
    assert run("--user", "start", UNIT).returncode == 0
    assert state("--user", "show", "-p", "ActiveState", "--value", UNIT) == "active"
    assert state("--user", "show", UNIT) == "ActiveState=active"
    assert run("--user", "stop", UNIT).returncode == 0
    assert state("--user", "show", "-p", "ActiveState", "--value", UNIT) == "inactive"

    for args, expected in (
        (("--user", "start", "other.service"), "unsupported unit"),
        (("start", UNIT), "only --user"),
        (("--user", "restart", UNIT), "unknown command"),
        (("--user", "show", "-p", "Other", "--value", UNIT), "unsupported show"),
    ):
        out = run(*args)
        assert out.returncode != 0, args
        assert expected in out.stderr, (args, out.stderr)

    lines = log.read_text().splitlines()
    assert any(line.startswith("start " + UNIT) for line in lines)
    assert any(line.startswith("stop " + UNIT) for line in lines)
