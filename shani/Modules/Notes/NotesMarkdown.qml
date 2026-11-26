// A reading view for a note. The Markdown subset is parsed here and drawn with
// PlainText Text items: a note never becomes an HTML string, so <script>,
// attributes and entities in its body cannot be interpreted by the renderer.
// Only wiki: and http(s): links found by the parser are activatable.
import QtQuick
import QtQuick.Layouts
import qs.Common

Item {
    id: doc
    property string markdown: ""
    signal wikiLink(string name)
    signal webLink(string url)

    /// Text runs, split on whitespace so a Flow can wrap a paragraph normally.
    function pushWords(out, s) {
        String(s).split(/(\s+)/).forEach(w => { if (w !== "") out.push({ text: w }); });
    }

    /// Inline markers, in priority order: code, bold, wiki link, web link, italic.
    function parseInline(s) {
        const out = [];
        const src = String(s === undefined || s === null ? "" : s);
        const re = /`([^`\n]+)`|\*\*([^*\n]+)\*\*|\[\[([^\[\]\n]+)\]\]|\[([^\]\n]+)\]\(([^)\s'"]+)\)|\*([^*\n]+)\*/g;
        let last = 0, m;
        while ((m = re.exec(src)) !== null) {
            if (m.index > last) pushWords(out, src.slice(last, m.index));
            if (m[1] !== undefined) out.push({ text: m[1], code: true });
            else if (m[2] !== undefined) out.push({ text: m[2], bold: true });
            else if (m[3] !== undefined) out.push({ text: "[[" + m[3] + "]]", target: "wiki:" + m[3] });
            else if (m[4] !== undefined) {
                const url = m[5];
                // an unknown scheme stays visible as text and is never clicked
                if (/^https?:\/\//.test(url)) out.push({ text: m[4], target: url });
                else out.push({ text: m[4] + "(" + url + ")" });
            } else if (m[6] !== undefined) out.push({ text: m[6], italic: true });
            last = re.lastIndex;
        }
        if (last < src.length) pushWords(out, src.slice(last));
        return out;
    }

    /// Blocks of one line each (fenced code spans several). No HTML anywhere.
    function parseMarkdown(md) {
        const blocks = [];
        const lines = String(md === undefined || md === null ? "" : md).split(/\r?\n/);
        let code = null;
        lines.forEach(line => {
            if (/^\s*```/.test(line)) {
                if (code !== null) { blocks.push({ kind: "code", text: code.join("\n") }); code = null; }
                else code = [];
                return;
            }
            if (code !== null) { code.push(line); return; }
            const h = /^\s*(#{1,6})\s+(.*)$/.exec(line);
            if (h) {
                blocks.push({ kind: "heading", level: h[1].length, runs: parseInline(h[2]) });
                return;
            }
            const item = /^\s*[-*+]\s+(.*)$/.exec(line);
            if (item) {
                const box = /^\[([ xX])\]\s*(.*)$/.exec(item[1]);
                const runs = parseInline(box ? box[2] : item[1]);
                runs.unshift({ text: box ? (box[1].toLowerCase() === "x" ? "☑ " : "☐ ") : "• ", muted: true });
                blocks.push({ kind: "list", runs: runs });
                return;
            }
            if (/^\s*>\s?/.test(line)) {
                const runs = parseInline(line.replace(/^\s*>\s?/, ""));
                runs.unshift({ text: "│ ", muted: true });
                blocks.push({ kind: "quote", runs: runs });
                return;
            }
            if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { blocks.push({ kind: "rule" }); return; }
            if (line.trim() !== "") blocks.push({ kind: "paragraph", runs: parseInline(line) });
        });
        if (code !== null) blocks.push({ kind: "code", text: code.join("\n") });
        return blocks;
    }

    function activate(run) {
        if (!run || !run.target) return;
        if (run.target.indexOf("wiki:") === 0) doc.wikiLink(run.target.slice(5));
        else if (/^https?:\/\//.test(run.target)) doc.webLink(run.target);
    }

    readonly property var blocks: parseMarkdown(markdown)

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.px(6)

        Repeater {
            model: doc.blocks
            delegate: ColumnLayout {
                id: block
                required property var modelData
                Layout.fillWidth: true
                Layout.topMargin: modelData.kind === "heading" ? Theme.px(6) : 0
                spacing: Theme.px(2)

                Flow {
                    Layout.fillWidth: true
                    visible: block.modelData.kind !== "code" && block.modelData.kind !== "rule"
                    spacing: 0
                    Repeater {
                        model: block.modelData.runs || []
                        Text {
                            id: runText
                            required property var modelData
                            textFormat: Text.PlainText
                            text: modelData.text
                            color: modelData.target ? Theme.accent : (modelData.muted ? Theme.dim : Theme.text)
                            font.family: modelData.code ? Theme.mono : Theme.font
                            font.pixelSize: (block.modelData.level === 1 ? Theme.px(17)
                                : block.modelData.level === 2 ? Theme.px(15)
                                : block.modelData.level > 0 ? Theme.px(14)
                                : Theme.px(13)) * Theme.fontScale
                            font.bold: !!modelData.bold || block.modelData.level > 0
                            font.italic: !!modelData.italic || block.modelData.kind === "quote"
                            Accessible.role: modelData.target ? Accessible.Link : Accessible.NoRole
                            Accessible.name: modelData.target
                                ? (modelData.target.indexOf("wiki:") === 0
                                    ? Tr.t("Wiki link %1").arg(modelData.text)
                                    : Tr.t("Link %1").arg(modelData.target))
                                : modelData.text
                            MouseArea {
                                anchors.fill: parent
                                visible: !!runText.modelData.target
                                cursorShape: Qt.PointingHandCursor
                                onClicked: doc.activate(runText.modelData)
                            }
                            KeyFocus {
                                visible: !!runText.modelData.target
                                name: runText.Accessible.name
                                onActivated: doc.activate(runText.modelData)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: block.modelData.kind === "code"
                    color: Theme.surface1
                    radius: Theme.radiusSmall
                    implicitHeight: codeText.implicitHeight + Theme.px(10)
                    Text {
                        id: codeText
                        anchors { fill: parent; margins: Theme.px(5) }
                        textFormat: Text.PlainText
                        text: block.modelData.text || ""
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: Theme.type("body")
                        wrapMode: Text.WrapAnywhere
                        Accessible.name: Tr.t("Code block")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    visible: block.modelData.kind === "rule"
                    color: Theme.border
                    Accessible.ignored: true
                }
            }
        }
    }
}
