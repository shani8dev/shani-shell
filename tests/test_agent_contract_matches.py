"""The shell's Agent XML is Chronoa's Agent XML, not a close approximation.

test_agent_contract.py only compares method names and arg direction after
dropping arg names and signals. A method the shell calls with the wrong arg
type, or a signal it never subscribes to, fails at run time. This test compares
the whole shape - method args, signals, interface and bus names - against the
read-only Chronoa checkout beside this repo, with a negative control.
"""

from __future__ import annotations

import importlib.util
import re
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "bridge/agent_contract.py"
CHRONOA = ROOT.parent / (
    "shani-chronoa/usr/lib/shani-chronoa/shani_chronoa/agent_contract.py"
)

pytestmark = pytest.mark.skipif(
    not CHRONOA.exists(), reason="no shani-chronoa checkout beside this repo"
)


def load(path: Path):
    spec = importlib.util.spec_from_file_location("contract_" + path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def xml_text(path: Path) -> str:
    text = path.read_text()
    return re.search(r'XML = f?"""(.*?)"""', text, re.S).group(1)


def parse(xml: str) -> dict:
    xml = xml.replace("{IFACE}", "dev.shani.chronoa.Agent")
    xml = re.sub(r"<!DOCTYPE[^>]*>", "", xml, flags=re.S)
    node = ET.fromstring(xml.strip())
    iface = node.find("interface")
    return {
        "interface": iface.get("name"),
        "methods": {
            m.get("name"): [
                (a.get("name"), a.get("type"), a.get("direction"))
                for a in m.iter("arg")
            ]
            for m in node.iter("method")
        },
        "signals": {
            s.get("name"): [(a.get("name"), a.get("type")) for a in s.iter("arg")]
            for s in node.iter("signal")
        },
    }


def test_bus_names_match_chronoa():
    shell, chronoa = load(SHELL), load(CHRONOA)
    for name in ("BUS_NAME", "PATH", "IFACE"):
        assert getattr(shell, name) == getattr(chronoa, name), name


def test_whole_interface_shape_matches_chronoa():
    assert parse(xml_text(SHELL)) == parse(xml_text(CHRONOA))


def test_a_changed_argument_is_caught():
    # Negative control: the comparison cannot pass a drifted contract.
    changed = xml_text(SHELL).replace(
        '<arg name="section" type="s" direction="in"/>',
        '<arg name="section" type="i" direction="in"/>',
    )
    assert changed != xml_text(SHELL)
    assert parse(changed) != parse(xml_text(CHRONOA))
