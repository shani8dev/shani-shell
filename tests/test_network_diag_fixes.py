"""Static asserts for the pass-19 network-diagnostics copy/verification fixes.

The three gaps checked here are user-visible: a Wi-Fi failure reason used to be
thrown away, a hidden-network failure showed raw nmcli stderr, and applying DNS
never checked that the new resolver actually answers.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def test_wifi_failure_reason_is_mapped_instead_of_discarded():
    text = source("shani/Modules/ControlCenter/SidebarDetails.qml")
    assert "function failureText(reason)" in text
    assert "wifiList.failedReason = wifiList.failureText(reason)" in text
    assert "wifiList.failedReason ||" in text  # subtitle uses the mapped copy
    assert "Couldn’t connect — check the password" not in text  # old fixed message gone
    # a few distinct causes, each with a next step, plus a generic fallback
    for copy in (
        "Wrong password",
        "802.1X",
        "out of range",
        "address from the router",
        "Couldn't connect — try again",
    ):
        assert copy in text, copy
    for reason in ('r === "1"', 'r === "3"', 'r === "4"', 'r === "5"'):
        assert reason in text, reason


def test_hidden_network_failure_hides_raw_cli_text_behind_details():
    net = source("shani/Services/Net.qml")
    assert "property string hiddenRaw" in net
    assert "function hiddenFailure(raw)" in net
    assert "root.hiddenFailure(raw)" in net  # status gets friendly copy
    assert 'root.hiddenRaw = code === 0 ? "" : raw' in net
    assert 'Tr.t("Couldn\'t connect to the hidden network — try again")' in net

    side = source("shani/Modules/ControlCenter/SidebarDetails.qml")
    assert 'title: Tr.t("Show error details")' in side
    assert "text: Net.hiddenRaw" in side  # raw line only in that row
    assert "hiddenDetailsOpen" in side


def test_dns_change_is_verified_with_a_bounded_lookup():
    text = source("shani/Modules/Settings/SettingsNetwork.qml")
    assert "id: dnsVerify" in text
    assert "timeout 5 getent hosts" in text  # bounded DNS query
    assert "dnsVerify.running = true" in text  # only after a successful apply
    assert 'Tr.t("DNS applied — a test lookup worked")' in text
    assert (
        'Tr.t("DNS applied, but a test lookup failed — check the server addresses")'
        in text
    )
    assert "page.noteOk ? Theme.text : Theme.danger" in text
