// Settings > Chronoa: one read-only page for every inventory section. It asks
// the shell's bridge for one bounded section and draws what comes back; no
// value is typed, edited or acted on here. The words for each row come from
// ChronoaInventory.js, which only maps data to plain title/subtitle/icon.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import "ChronoaInventory.js" as Inventory

ColumnLayout {
    id: root
    property string section: "status"
    property bool active: true

    readonly property bool ready: root.haveReply && !root.failed
    readonly property string error: root.failed ? root.failText : ""
    readonly property int count: root.shown.length
    // title + subtitle, so a live check can see the data, not only the row label
    readonly property var sample: root.shown.slice(0, 4).map(item => {
        var d = Inventory.describe(root.section, item);
        return [d.title, d.subtitle].filter(Boolean).join(": ");
    })

    property bool busy: false
    property bool haveReply: false
    property bool failed: false
    property string failText: ""
    property var items: []          // raw reply data: a list, or a dict for status/privacy
    property var shown: []
    property string reqId: ""
    property int seq: 0

    signal report(var info)

    onActiveChanged: if (active) root.request()
    onSectionChanged: root.request()
    Component.onCompleted: root.request()

    function publish() {
        root.report({ ready: root.ready, error: root.error, count: root.count, sample: root.sample });
    }

    function applyItems() {
        root.shown = root.failed ? []
            : Inventory.expand(root.section, root.items,
                               { ready: root.ready, service: ChronoaEngine.service });
    }

    function request() {
        root.seq += 1;
        root.reqId = "inv" + root.seq + "-" + root.section;
        root.busy = true;
        root.haveReply = false;
        root.failed = false;
        root.failText = "";
        root.items = [];
        root.shown = [];
        root.publish();
        if (!Bridge.send({ op: "inventory", id: root.reqId, section: root.section, limit: 100 })) {
            root.busy = false;
            root.failed = true;
            root.failText = Tr.t("Chronoa is not running");
            root.publish();
        }
    }

    Connections {
        target: Bridge
        function onMessage(msg) {
            if (!msg || msg.type !== "inventory" || msg.id !== root.reqId) return;
            root.busy = false;
            root.haveReply = true;
            root.failed = !!msg.error;
            root.failText = msg.error ? String(msg.error) : "";
            root.items = msg.items === undefined ? [] : msg.items;
            root.applyItems();
            root.publish();
        }
    }

    Connections {
        target: ChronoaEngine
        function onServiceChanged() { if (root.haveReply) { root.applyItems(); root.publish(); } }
    }

    InfoBanner {
        visible: root.section === "privacy" || root.section === "senses"
        Layout.fillWidth: true
        tone: "info"
        text: Tr.t("Changing these comes next.")
    }

    InfoBanner {
        visible: root.section === "conversations"
        Layout.fillWidth: true
        tone: "info"
        text: Tr.t("Saved talks are read-only here.")
    }

    BusyNote {
        visible: root.busy
        Layout.fillWidth: true
        note: Tr.t("Reading Chronoa's saved information…")
    }

    EmptyState {
        visible: !root.busy && (root.failed || root.shown.length === 0)
        Layout.fillWidth: true
        icon: root.failed ? "dialog-warning" : "preferences-system"
        title: root.failed ? Tr.t("Chronoa is not running") : Tr.t("Nothing here yet")
        subtitle: root.failed ? root.failText : Tr.t("There is nothing saved in this section yet.")
    }

    Repeater {
        model: root.shown
        ListRow {
            Layout.fillWidth: true
            interactive: false
            property var rowData: Inventory.describe(root.section, modelData)
            icon: rowData.icon || ""
            title: rowData.title || ""
            subtitle: rowData.subtitle || ""
        }
    }
}
