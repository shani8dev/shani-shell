"""Static checks for the pass-22 audio / TTS fixes."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text()


def test_balance_reapplied_on_volume_change():
    q = read("shani/Services/Audio.qml")
    # a scalar volume write flattens the channel volumes carrying the balance,
    # so it must be re-applied on volume change - without chasing its own pactl echo
    assert "onVolumeChanged: { if (!root.balanceWriting) balanceApply.restart(); }" in q
    assert "property bool balanceWriting: false" in q
    assert "Process { id: pactl; onExited: root.balanceWriting = false }" in q


def test_real_percent_exposed_and_used():
    a = read("shani/Services/Audio.qml")
    assert "readonly property int realPercent: Math.round(volume * 100)" in a
    s = read("shani/Modules/ControlCenter/SidebarSliders.qml")
    # fill stays volume/maxVolume; the tip / accessible name carries the true percent
    assert "value: Audio.volume / Audio.maxVolume" in s
    assert 'label: Tr.t("Volume %1%", Audio.realPercent)' in s


def test_speak_honours_notification_hints():
    q = read("shani/Services/Speak.qml")
    assert "import Quickshell.Services.Notifications" in q
    assert '["suppress-sound"]' in q
    assert "NotificationUrgency.Critical" in q
    assert 'Tr.t("Important alert")' in q


def test_speak_exposes_last_utterance():
    q = read("shani/Services/Speak.qml")
    assert 'property string last: ""' in q
    assert "last = text.slice" in q
