pragma Singleton
// Suggested replies for a message notification that can be answered in place
// (an app offering inline reply: Shani Link's texts, chat apps): three short
// answers Chronoa writes (Agent.Write - the model alone, no tools, nothing in
// the conversation), shown as chips on the card; one click sends it as the
// reply. Settings > Notifications turns them off. Never for a hidden-content
// notification (it would put the message on the screen and send it to the model).
import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root
    property var suggestions: ({})      // notification id -> ["Sure!", ...]
    property var asked: ({})            // ids already asked about
    readonly property bool enabled: Settings.data.smartReplies !== false

    function forId(id) { return suggestions[id] || []; }

    function suggest(n) {
        if (!enabled || !n || !n.hasInlineReply || asked[n.id] || Settings.data.notifHideContent)
            return;
        const a = Object.assign({}, asked);
        a[n.id] = true;
        asked = a;
        const message = (n.summary || "") + (n.body ? "\n" + n.body : "");
        if (!message.trim())
            return;
        Bridge.send({
            op: "write", id: "r" + n.id,
            instruction: "Suggest three short, natural replies to this message, each under eight words, one per line, "
                + "without numbers or quotes. Write them in the language the message is written in.",
            text: (n.appName ? n.appName + ": " : "") + message
        });
    }

    // a reply line as the model may write it: "1. Sure!", "- Sure!", "\"Sure!\""
    function clean(line) {
        return String(line).replace(/^\s*(?:\d+[.)]|[-*•])\s*/, "").replace(/^["“'](.*)["”']$/, "$1").trim();
    }

    Connections {
        target: Bridge
        function onMessage(msg) {
            if (msg.type !== "written" || String(msg.id).charAt(0) !== "r" || msg.error)
                return;
            const id = Number(String(msg.id).slice(1));
            const lines = String(msg.text || "").split("\n").map(root.clean).filter(l => l && l.length <= 80);
            if (!lines.length)
                return;
            const s = Object.assign({}, root.suggestions);
            s[id] = lines.slice(0, 3);
            root.suggestions = s;
        }
    }
}
