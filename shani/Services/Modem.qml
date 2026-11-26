pragma Singleton
// The SIM modem (bridge/modem.py over ModemManager): unlock the SIM, texts in
// and out, and calls where the modem has voice. A text that carries a one-time
// code offers to copy it. Call audio is the hardware's — on most laptop modems
// only a phone over Bluetooth (Chronoa) carries sound, so "Call" goes there
// when this modem has no voice.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import "../Common/ToolPath.js" as ToolPath

Singleton {
    id: root
    readonly property string tool: ToolPath.of(Quickshell.env("SHANI_MODEM_TOOL"), "modem.py")
    property var modem: null              // { path, state, locked, operator, signal, number, voice, messaging }
    property var call: null               // the call in progress: { path, number, state, incoming }
    property int callSeconds: 0
    readonly property string callTime: Math.floor(callSeconds / 60) + ":" + String(callSeconds % 60).padStart(2, "0")
    property var waitingCall: null          // a second call, waiting while one is up
    property bool muted: false              // live-call controls, echoed by the bridge
    property bool speaker: false
    property string error: ""
    property var lastSms: null
    readonly property bool canCall: modem !== null && modem.voice && modem.locked === ""
    readonly property bool canText: modem !== null && modem.messaging && modem.locked === ""

    function send(msg) { bridge.write(JSON.stringify(msg) + "\n"); }
    function unlock(pin) { error = ""; send({ pin: pin }); }
    function text(to, body) { error = ""; send({ sms: { to: to, text: body } }); }
    function dial(number) { error = ""; send({ call: number }); }
    function answer() { if (call) answerCall(call.path); }
    function answerCall(path) { if (path) send({ answer: path }); }
    function hangup() { if (call) send({ hangup: call.path }); }
    // the modem has no ModemManager verb for these: the bridge echoes them back
    function callctl(action, on) { send({ callctl: { action: action, on: on !== false } }); }
    function setMute(on) { root.muted = !!on; callctl("mute", root.muted); }
    function setSpeaker(on) { root.speaker = !!on; callctl("speaker", root.speaker); }
    // a number to call: the modem when it can, otherwise Chronoa (a phone over Bluetooth)
    // a number to call: shani-shell's dial pad, filled in (it picks the line - landline,
    // phone or this modem - and nothing is dialled until Call is pressed)
    // Contacts / "Call" landing: the dial pad is the first action when a phone
    // link is available (Services/Phone tries phone-app directly); else
    // the tel: handler (dev.shani.Shell.Phone.Dial.desktop, also shani-shell --dial).
    function callNumber(number) {
        const n = (number || "").replace(/[\s-]/g, "");
        if (Phone.available || Phone.reachable)
            Phone.openDial(n);
        else
            Qt.openUrlExternally("tel:" + n);
    }
    // "Your code is 482913" → 482913
    function codeIn(t) { const m = /(?:^|\D)(\d{4,8})(?:\D|$)/.exec(t || ""); return m ? m[1] : ""; }

    Process {
        id: bridge
        running: true
        command: ["python3", root.tool]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if ("modem" in m) {
                    const wasLocked = root.modem && root.modem.locked;
                    root.modem = m.modem;
                    if (m.modem && m.modem.locked && !wasLocked)
                        pinAsk.running = true;
                } else if (m.sms) {
                    root.lastSms = m.sms;
                    smsComp.createObject(root, { sms: m.sms });
                } else if (m.call) {
                    const c = m.call;
                    if (c.state === "terminated") {
                        if (root.call && root.call.path === c.path) {
                            root.call = null;
                            root.callSeconds = 0;
                            root.muted = false;
                            root.speaker = false;
                        } else if (root.waitingCall && root.waitingCall.path === c.path)
                            root.waitingCall = null;
                        return;
                    }
                    // a waiting call must not replace the one already up
                    if (c.state === "waiting") {
                        if (!root.call || root.call.path !== c.path)
                            root.waitingCall = c;
                        return;
                    }
                    if (c.state === "held") {
                        if (root.call && root.call.path === c.path) root.call = c;
                        return;
                    }
                    const fresh = !root.call || root.call.path !== c.path;
                    if (root.waitingCall && root.waitingCall.path === c.path) root.waitingCall = null;
                    root.call = c;
                    // ringing is shani-shell's notification (it owns calls on every line):
                    // ringing here as well put two on screen for one call
                    if (fresh)
                        root.callSeconds = 0;
                } else if (m.callctl) {
                    if (m.callctl.action === "mute") root.muted = m.callctl.on;
                    else if (m.callctl.action === "speaker") root.speaker = m.callctl.on;
                } else if (m.error)
                    root.error = m.error;
                else if (m.sent)
                    Quickshell.execDetached(["notify-send", "-a", "Messages", "-i", "mail-send", "Text sent", "to " + m.sent.to]);
            }
        }
    }
    Timer { running: root.call !== null && root.call.state === "active"; interval: 1000; repeat: true; onTriggered: root.callSeconds++ }

    // the SIM wants its PIN
    Process {
        id: pinAsk
        command: ["notify-send", "-a", "Mobile", "-i", "network-cellular-offline", "-u", "critical", "-A", "unlock=Unlock", "The SIM card is locked", "Enter its PIN to use mobile data, texts and calls"]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "unlock") Ui.modemDialog = "pin" }
    }
    // a text: Reply, and Copy code when it carries one
    Component {
        id: smsComp
        Process {
            id: n
            property var sms
            readonly property string code: root.codeIn(sms.text)
            running: true
            command: ["notify-send", "-a", "Messages", "-i", "mail-unread", "-A", "reply=Reply"].concat(code ? ["-A", "code=Copy " + code] : [])
                .concat([sms.from, sms.text])
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim();
                    if (a === "reply") { Ui.smsTo = n.sms.from; Ui.modemDialog = "sms"; }
                    else if (a === "code") Quickshell.clipboardText = n.code;
                    n.destroy();
                }
            }
        }
    }
    // incoming-call Answer/Decline UI is shani-shell's notification path
    // (phone/missed_call.py + incoming_call.py); this shell never
    // duplicated it. See shani-shell/AGENTS.md "desktop-neutral plumbing".
}
