// Text that highlights every occurrence of `needle` inside `text`.
// Uses rich text so all Text properties (elide, sizing, layout) keep working.
import QtQuick
import qs.Common

Text {
    id: root
    property string needle: ""
    property color highlightColor: Theme.accent
    property color highlightBg: Theme.accentSoft

    textFormat: Text.RichText
    // raw input label; `text` becomes the rich (highlighted) version
    property string sourceText: ""

    readonly property string rich: {
        const t = String(root.sourceText || "");
        const n = String(root.needle || "").trim();
        if (n === "")
            return escapeHtml(t);
        const low = t.toLowerCase();
        const q = n.toLowerCase();
        let out = "";
        let i = 0;
        while (true) {
            const idx = low.indexOf(q, i);
            if (idx < 0) {
                out += escapeHtml(t.slice(i));
                break;
            }
            if (idx > i)
                out += escapeHtml(t.slice(i, idx));
            out += '<span style="background-color:' + root.highlightBg + ';color:' + root.highlightColor + ';border-radius:2px;">'
                + escapeHtml(t.slice(idx, idx + n.length)) + '</span>';
            i = idx + n.length;
        }
        return out;
    }

    text: root.rich

    function escapeHtml(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
}
