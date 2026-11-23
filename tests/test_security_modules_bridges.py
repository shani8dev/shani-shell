import json, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent

def test_security_status_shape():
    r = subprocess.run([sys.executable, str(ROOT / 'bridge/security.py'), 'status'], capture_output=True, text=True)
    d = json.loads(r.stdout)
    assert {'lsm','apparmor','pwquality','audit'} <= set(d)

def test_modules_list_shape():
    r = subprocess.run([sys.executable, str(ROOT / 'bridge/modules.py'), 'list'], capture_output=True, text=True)
    d = json.loads(r.stdout)
    assert 'modules' in d and 'count' in d
