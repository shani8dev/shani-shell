// Database browser (Modules/DatabaseBrowser.qml): a small SQLite reader. The
// path and the SQL are passed to one fixed Python script as argv — a table or
// column name can contain quotes, spaces or shell characters without ever
// becoming shell code. The connection is read-only, rows are capped, and every
// outcome (tables, results, errors) is one JSON line on stdout.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common

AppWindow {
    id: win
    appName: "Database browser"
    visible: Ui.databaseBrowser
    onGone: Ui.databaseBrowser = false
    implicitWidth: Theme.px(900)
    implicitHeight: Theme.px(640)

    // fixed code: sys.argv[1] is the file, sys.argv[2] the statement. No user
    // text is ever concatenated into this string or into a shell command.
    readonly property string pyCode: `
import sqlite3, sys, json
from urllib.parse import quote
path, sql = sys.argv[1], sys.argv[2]
try:
    db = sqlite3.connect("file:" + quote(path) + "?mode=ro", uri=True)
    cur = db.cursor()
    cur.execute(sql)
    if cur.description:
        cols = [d[0] for d in cur.description]
        rows = [list(r) for r in cur.fetchmany(200)]
        print(json.dumps({"columns": cols, "rows": rows, "count": len(rows), "truncated": len(rows) == 200}, default=str))
    else:
        print(json.dumps({"columns": [], "rows": [], "status": "OK: " + str(cur.rowcount) + " row(s)"}, default=str))
    db.close()
except Exception as e:
    print(json.dumps({"error": str(e)[:300]}, default=str))
`
    readonly property string listSql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"

    property string dbPath: ""
    property string sql: ""
    property var tables: []
    property var columns: []
    property var rows: []
    property var history: []
    property string error: ""
    property string status: ""
    property bool busy: false
    property bool cancelled: false
    property bool truncated: false
    readonly property bool hasDb: win.dbPath.trim() !== ""
    readonly property string message: win.error !== "" ? win.error : win.status

    // a name read out of sqlite_master is data: quote it as an SQL identifier
    function quoteIdent(name) { return '"' + String(name).replace(/"/g, '""') + '"'; }
    function pushHistory(s) {
        const h = win.history.filter(x => x !== s);   // newest first, no repeats
        h.unshift(s);
        win.history = h.slice(0, 20);
    }
    function listTables() {
        const p = win.dbPath.trim();
        win.error = "";
        win.tables = [];
        if (p === "") return;
        listProc.command = ["python3", "-c", win.pyCode, p, win.listSql];
        listProc.running = true;
    }
    function runQuery(q) {
        const s = (q === undefined ? win.sql : q).trim();
        if (win.busy) return;
        if (s === "") { win.error = Tr.t("Write a query first"); return; }
        if (!win.hasDb) { win.error = Tr.t("Open a database file first"); return; }
        win.error = ""; win.status = ""; win.cancelled = false; win.busy = true;
        win.pushHistory(s);
        queryProc.command = ["python3", "-c", win.pyCode, win.dbPath.trim(), s];
        queryProc.running = true;
    }
    function cancelQuery() {
        win.cancelled = true;
        queryProc.running = false;
        win.busy = false;
        win.status = Tr.t("Query cancelled");
    }
    function openTable(name) {
        win.sql = "SELECT * FROM " + win.quoteIdent(name) + " LIMIT 200";
        win.runQuery(win.sql);
    }

    onDbPathChanged: win.listTables()
    // Files hands a .db path over on the clipboard before opening this window
    onVisibleChanged: {
        if (!visible) return;
        const seed = String(Quickshell.clipboardText || "").trim();
        if (win.dbPath.trim() === "" && seed.startsWith("/") && /\.(db|sqlite|sqlite3)$/i.test(seed))
            win.dbPath = seed;
        win.listTables();
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("Could not read the database") }; }
                win.error = r.error || "";
                win.tables = win.error ? [] : (r.rows || []).map(row => row[0]).filter(x => !!x);
            }
        }
    }
    Process {
        id: queryProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (win.cancelled) { win.cancelled = false; return; }
                win.busy = false;
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { error: Tr.t("Could not read the result") }; }
                if (r.error) {
                    win.error = r.error;
                    win.columns = []; win.rows = []; win.status = ""; win.truncated = false;
                    return;
                }
                win.error = "";
                win.columns = r.columns || [];
                win.rows = r.rows || [];
                win.truncated = !!r.truncated;
                win.status = r.status || Tr.t("%1 row(s)").arg(String(win.rows.length))
                             + (win.truncated ? " " + Tr.t("(first 200)") : "");
            }
        }
        onExited: code => { if (code !== 0 && !win.cancelled && win.error === "") win.error = Tr.t("The query could not run"); }
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.visible = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(10)

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Database") }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                TextField {
                    id: pathField
                    Layout.fillWidth: true
                    label: Tr.t("Database file")
                    placeholder: Tr.t("Path to a .db or .sqlite file")
                    text: win.dbPath
                    onEditingFinished: win.dbPath = text.trim()
                    Keys.onAccepted: win.dbPath = text.trim()
                }
                IconButton {
                    icon: "view-refresh"; tip: Tr.t("Reload tables")
                    Accessible.name: Tr.t("Reload tables")
                    onClicked: win.listTables()
                }
                Spinner { visible: listProc.running || win.busy; size: Theme.px(16)
                          Layout.preferredWidth: Theme.px(16); Layout.preferredHeight: Theme.px(16) }
            }
            Text {
                Layout.fillWidth: true
                visible: listProc.running || win.busy
                text: win.busy ? Tr.t("Running query…") : Tr.t("Reading tables…")
                color: Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: text
            }
            Text {
                Layout.fillWidth: true
                visible: win.message !== ""
                text: win.message
                color: win.error !== "" ? Theme.danger : Theme.dim
                wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: win.message
            }

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Tables") }
            Flow {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Repeater {
                    model: win.tables
                    Choice {
                        required property string modelData
                        text: modelData
                        Accessible.name: Tr.t("Query table %1").arg(modelData)
                        onClicked: win.openTable(modelData)
                    }
                }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: !listProc.running && win.error === "" && win.tables.length === 0
                icon: "document-open"
                title: win.hasDb ? Tr.t("No tables in this database") : Tr.t("No database open")
                subtitle: win.hasDb ? Tr.t("The file may be empty or not a SQLite database")
                                    : Tr.t("Type a path above, then press Enter")
                actionText: win.hasDb ? Tr.t("Reload tables") : ""
                onAction: win.listTables()
            }

            SectionTitle { Layout.fillWidth: true; text: Tr.t("SQL query") }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: Theme.px(104)
                color: Theme.surface1; radius: Theme.radiusSmall
                border.width: 1; border.color: sqlEdit.activeFocus ? Theme.accent : Theme.stroke
                Flickable {
                    anchors.fill: parent; anchors.margins: Theme.px(8); clip: true
                    contentWidth: width; contentHeight: Math.max(sqlEdit.implicitHeight, height)
                    TextArea {
                        id: sqlEdit
                        width: parent.width
                        wrapMode: TextArea.Wrap
                        textFormat: Text.PlainText
                        placeholderText: Tr.t("SELECT * FROM …  (Ctrl+Enter to run)")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                        Accessible.name: Tr.t("SQL query")
                        onTextChanged: win.sql = text
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Return && (e.modifiers & Qt.ControlModifier)) { win.runQuery(); e.accepted = true; }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Button {
                    kind: "primary"; text: Tr.t("Run query")
                    enabled: win.hasDb && win.sql.trim() !== "" && !win.busy
                    busy: win.busy
                    onClicked: win.runQuery()
                }
                Button {
                    text: Tr.t("Cancel"); enabled: win.busy
                    Accessible.name: Tr.t("Cancel the running query")
                    onClicked: win.cancelQuery()
                }
                Button {
                    flat: true; text: Tr.t("Clear history"); enabled: win.history.length > 0
                    onClicked: win.history = []
                }
                Button {
                    flat: true; text: Tr.t("Copy query"); enabled: win.sql.trim() !== ""
                    Accessible.name: Tr.t("Copy the SQL query to the clipboard")
                    onClicked: Quickshell.clipboardText = win.sql
                }
            }

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Results") }
            ListView {
                id: grid
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: win.rows
                spacing: 1
                Accessible.name: Tr.t("Query results")
                header: Rectangle {
                    width: grid.width; height: Theme.px(32); radius: Theme.radiusSmall; color: Theme.surface1
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Theme.px(6); anchors.rightMargin: Theme.px(6)
                        spacing: Theme.px(6)
                        Repeater {
                            model: win.columns
                            Text {
                                required property string modelData
                                Layout.fillWidth: true; text: modelData
                                color: Theme.dim; elide: Text.ElideRight
                                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                                font.weight: Font.DemiBold
                                Accessible.name: Tr.t("Column %1").arg(modelData)
                            }
                        }
                    }
                }
                delegate: Rectangle {
                    id: cellRow
                    required property var modelData
                    width: grid.width; height: Theme.px(30); radius: Theme.radiusSmall; color: Theme.surface1
                    Accessible.name: win.columns.map((c, i) => c + ": " + modelData[i]).join(", ")
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Theme.px(6); anchors.rightMargin: Theme.px(6)
                        spacing: Theme.px(6)
                        Repeater {
                            model: win.columns
                            Text {
                                Layout.fillWidth: true
                                text: cellRow.modelData[index] === null ? Tr.t("(null)") : String(cellRow.modelData[index])
                                color: Theme.text; elide: Text.ElideRight
                                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                            }
                        }
                    }
                }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: !win.busy && win.error === "" && win.columns.length === 0 && win.rows.length === 0
                icon: "view-list-details"; title: Tr.t("Nothing to show yet")
                subtitle: Tr.t("Pick a table or write a query, then press Run")
            }
            Text {
                Layout.fillWidth: true
                visible: !win.busy && win.error === "" && win.columns.length > 0 && win.rows.length === 0
                text: Tr.t("The query returned no rows")
                color: Theme.dim
                font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                Accessible.role: Accessible.StaticText; Accessible.name: text
            }

            SectionTitle { Layout.fillWidth: true; text: Tr.t("Query history") }
            Flow {
                Layout.fillWidth: true; spacing: Theme.px(6)
                Repeater {
                    model: win.history
                    Rectangle {
                        required property string modelData
                        width: Math.min(Theme.px(280), parent.width)
                        height: Theme.px(30); radius: Theme.radiusSmall
                        color: Theme.surface1; border.width: 1; border.color: Theme.stroke
                        Accessible.role: Accessible.Button
                        Accessible.name: Tr.t("Run again: %1").arg(modelData)
                        Text {
                            anchors.fill: parent; anchors.margins: Theme.px(6)
                            text: modelData; color: Theme.text; elide: Text.ElideMiddle
                            font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale
                        }
                        MouseArea { anchors.fill: parent; onClicked: win.runQuery(modelData) }
                        KeyFocus { onActivated: win.runQuery(modelData) }
                    }
                }
            }
        }
    }
}
