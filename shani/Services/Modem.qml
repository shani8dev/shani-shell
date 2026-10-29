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

Singleton {
    id: root
    readonly property string tool: Quickshell.env("SHANI_MODEM_TOOL") || "/usr/lib/shani-shell/modem.py"
    property var modem: null              // { path, state, locked, operator, signal, number, voice, messaging }
    property var call: null               // the call in progress: { path, number, state, incoming }
    property int callSeconds: 0
    readonly property string callTime: Math.floor(callSeconds / 60) + ":" + String(callSeconds % 60).padStart(2, "0")
    property string error: ""
    property var lastSms: null
    readonly property bool canCall: modem !== null && modem.voice && modem.locked === ""
    readonly property bool canText: modem !== null && modem.messaging && modem.locked === ""

    function send(msg) { bridge.write(JSON.stringify(msg) + "\n"); }
    function unlock(pin) { error = ""; send({ pin: pin }); }
    function text(to, body) { error = ""; send({ sms: { to: to, text: body } }); }
    function dial(number) { error = ""; send({ call: number }); }
    function answer() { if (call) send({ answer: call.path }); }
    function hangup() { if (call) send({ hangup: call.path }); }
    // a number to call: the modem when it can, otherwise Chronoa (a phone over Bluetooth)
    function callNumber(number) { canCall ? dial(number) : Chronoa.ask("Call " + number); }
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
                    if (m.call.state === "terminated") {
                        root.call = null;
                        return;
                    }
                    const fresh = !root.call || root.call.path !== m.call.path;
                    root.call = m.call;
                    if (fresh && m.call.state === "ringing-in")
                        ringComp.createObject(root, { number: m.call.number });
                    if (fresh)
                        root.callSeconds = 0;
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
    // a call coming in: Answer / Decline
    Component {
        id: ringComp
        Process {
            id: r
            property string number
            running: true
            command: ["notify-send", "-a", "Phone", "-i", "call-start", "-u", "critical", "-A", "answer=Answer", "-A", "decline=Decline", "Call from " + number, "on your SIM"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim();
                    if (a === "answer") root.answer();
                    else if (a === "decline") root.hangup();
                    r.destroy();
                }
            }
        }
    }
}
