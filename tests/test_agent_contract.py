"""The shell's copy of Chronoa's Agent interface (bridge/agent_contract.py, which
the bridge calls and dev/mock-chronoa.py registers) says what the real one
(shani-chronoa's agent_contract.py) says: a method the shell calls that Chronoa
does not have fails as UnknownMethod at run time, as Write once did in the mock."""
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHRONOA = ROOT.parent / "shani-chronoa/usr/lib/shani-chronoa/shani_chronoa/agent_contract.py"


def methods(path):
    text = path.read_text()
    xml = re.search(r'XML = f?"""(.*?)"""', text, re.S).group(1)
    xml = xml.replace("{IFACE}", "dev.shani.chronoa.Agent")
    xml = re.sub(r"<!DOCTYPE[^>]*>", "", xml)
    node = ET.fromstring(xml.strip())
    out = {}
    for m in node.iter("method"):
        out[m.get("name")] = [(a.get("type"), a.get("direction")) for a in m.iter("arg")]
    return out


def test_shell_copy_matches_chronoa():
    if not CHRONOA.exists():
        return
    assert methods(ROOT / "bridge/agent_contract.py") == methods(CHRONOA)


def test_the_mock_registers_the_shells_copy():
    assert "from agent_contract import XML as AGENT_XML" in (ROOT / "dev/mock-chronoa.py").read_text()
