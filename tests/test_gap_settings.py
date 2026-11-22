"""Settings gaps: removable media, DNS search domains, WWAN data cap."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def test_removable_media_defaults_cover_x_content_types():
    s = read("shani/Modules/Settings/SettingsDefaultApps.qml")
    assert "x-content/audio-cdda" in s
    assert "x-content/video-dvd" in s
    assert "x-content/image-dcf" in s
    assert "kinds.concat(mediaKinds)" in s
    assert 'Tr.t("Removable media")' in s


def test_dns_search_domains_are_written_through_nmcli():
    s = read("shani/Modules/Settings/SettingsNetwork.qml")
    assert "ipv4.dns-search" in s and "ipv6.dns-search" in s
    assert "function useDnsSearch(domains)" in s
    assert 'Tr.t("Search domains:' in s


def test_wwan_data_cap_is_kept_per_sim_connection():
    s = read("shani/Modules/Settings/SettingsNetwork.qml")
    assert "wwan-caps.json" in s
    assert "property var dataCaps" in s
    assert "function setCap(uuid, gb)" in s
    assert 'Tr.t("Monthly data cap (GB)")' in s
