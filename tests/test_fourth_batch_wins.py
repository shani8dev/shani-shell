"""Critical fixes from the final third-pass audits."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(p):
    return (ROOT / p).read_text()


def test_keyring_uses_attribute_lookup_not_object_path():
    s = read("shani/Services/Keyring.qml")
    assert '"lookup", id' in s
    assert '" put "' in s and '" drop "' in s
    assert "set_secret" not in s
    p = read("bridge/passwords.py")
    assert 'cmd == "put"' in p and 'cmd == "lookup"' in p and 'cmd == "drop"' in p
    assert 'cmd == "audit"' in p


def test_ai_providers_key_is_async_and_no_bogus_singleton():
    s = read("shani/Services/AIProviders.qml")
    assert 'Keyring.get("ai-provider-" + id, cb' in s
    assert "Passwords.getKey" not in s


def test_studio_clears_busy():
    s = read("shani/Services/Studio.qml")
    assert "function onBusyChanged()" in s
    assert "root.busy = false" in s


def test_hooks_do_not_splice_untrusted_paths():
    s = read("shani/Services/Hooks.qml")
    assert "cmd = cmd.replace(/\\$1/g" not in s
    assert '"sh", "-c", script, "sh", wallpaperPath' in s


def test_qr_tile_uses_runtime_dir_helper():
    s = read("shani/Modules/ControlCenter/SidebarTiles.qml")
    assert 'Qr.show(Tr.t("QR code"), text)' in s
    assert "/tmp/shani-qr.png" not in s


def test_password_audit_is_bridge_backed():
    s = read("shani/Modules/Passwords/PasswordsWindow.qml")
    assert '"audit"' in s
    assert "function runAudit()" in s
    assert "runAudit();" in s


def test_greeter_clears_password_on_user_change():
    s = read("greeter/shell.qml")
    assert s.count('pending = ""; pendingSet = false; passField.input.clear()') >= 2


def test_setup_minimum_password():
    s = read("setup/shell.qml")
    assert 'if (password.length < 8) return root.t("needPassword");' in s


def test_settings_quick_ops_are_real():
    s = read("shani/Modules/Settings/SettingsPage.qml")
    assert "quick-op.log" not in s
    assert "Backup.backupNow()" in s
    assert "shani-cassini" in s
    assert "SysStats.cpu * 100" in s


def test_webapps_no_undefined_safeurl():
    s = read("shani/Services/WebApps.qml")
    assert "safeUrl" not in s


def test_capture_fixes():
    assert "wl-copy" in read("shani/Services/Color.qml")
    assert '"yyyy-MM-dd HH-mm"' in read("shani/Services/Captions.qml")
    assert "stat -c %Y" in read("shani/Services/QuickLook.qml")
    assert "o.scale > 0 ? o.scale : 1.0" in read("shani/Services/Ruler.qml")
