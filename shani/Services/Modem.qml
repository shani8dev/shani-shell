pragma Singleton
// The SIM modem (bridge/modem.py over ModemManager): unlock the SIM, texts in
// and out, and calls where the modem has voice. Call audio is the hardware's;
// the shell draws the dial pad and the live call itself, on any line.
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Common
import qs.Services
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
    // A number to call opens the shell's own dial pad, filled in. It picks the
    // line (landline, phone or this modem); nothing is dialled until Call.
    function callNumber(number) {
        const n = (number || "").replace(/[\s-]/g, "");
        Phone.openDial(n);
    }
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
                        Ui.modemDialog = "pin";
                } else if (m.sms) {
                    root.lastSms = m.sms;
                    // the shell's own card asks for a reply, prefilled with this number
                    Ui.smsTo = m.sms.from;
                    Ui.modemDialog = "sms";
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
                    if (fresh)
                        root.callSeconds = 0;
                } else if (m.callctl) {
                    if (m.callctl.action === "mute") root.muted = m.callctl.on;
                    else if (m.callctl.action === "speaker") root.speaker = m.callctl.on;
                } else if (m.error)
                    root.error = m.error;
            }
        }
    }
    Timer { running: root.call !== null && root.call.state === "active"; interval: 1000; repeat: true; onTriggered: root.callSeconds++ }
}
