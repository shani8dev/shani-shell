// Settings > Default apps: which app opens links, mail, folders, text,
// pictures, video, music and PDFs — GLib's answer (`gio mime`), and its way of
// changing it (~/.config/mimeapps.list), so every app that asks agrees.
// Not xdg-mime: 1.2.1 reads mimeapps.list and then answers from the system's
// defaults anyway (measured), and exits 0 when it could not write the file.
// The candidates are the installed apps registered for that type.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data

    // the first type is the one asked about; all are set together
    readonly property var kinds: [
        { id: "browser", label: Tr.t("Web browser"), icon: "web-browser", types: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"] },
        { id: "mail", label: Tr.t("Mail"), icon: "mail-unread", types: ["x-scheme-handler/mailto"] },
        { id: "files", label: Tr.t("Files"), icon: "system-file-manager", types: ["inode/directory"] },
        { id: "text", label: Tr.t("Text"), icon: "text-x-generic", types: ["text/plain"] },
        { id: "images", label: Tr.t("Pictures"), icon: "image-x-generic", types: ["image/png", "image/jpeg", "image/webp", "image/gif"] },
        { id: "video", label: Tr.t("Video"), icon: "video-x-generic", types: ["video/mp4", "video/x-matroska", "video/webm"] },
        { id: "music", label: Tr.t("Music"), icon: "audio-x-generic", types: ["audio/mpeg", "audio/flac", "audio/ogg"] },
        { id: "pdf", label: Tr.t("PDF"), icon: "x-office-document", types: ["application/pdf"] }
    ]
    property var found: ({})              // id → { current, candidates: [] }
    property string open: ""              // the kind whose list is shown

    function entry(desktop) {
        return DesktopEntries.byId(desktop.replace(/\.desktop$/, "")) || null;
    }
    function nameOf(desktop) {
        const e = entry(desktop);
        return e ? e.name : (desktop ? desktop.replace(/\.desktop$/, "") : "None");
    }
    function refresh() {
        // gio mime: "Default application for “T”: X.desktop", then the registered ones, tab-indented
        query.command = ["sh", "-c", 'for k in "$@"; do id=${k%%=*}; m=${k#*=}; out=$(LC_ALL=C gio mime "$m" 2>/dev/null)
            cur=$(printf "%s\\n" "$out" | sed -n "s/^Default application for .*: //p")
            c=$(printf "%s\\n" "$out" | sed -n "/^Registered applications:/,/^[A-Z]/p" | sed -n "s/^\\t//p" | tr "\\n" ",")
            printf "%s\\t%s\\t%s\\n" "$id" "$cur" "$c"; done', "sh"].concat(kinds.map(k => k.id + "=" + k.types[0]));
        query.running = true;
    }
    onActiveChanged: if (active) refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) refresh()

    Process {
        id: query
        stdout: StdioCollector {
            onStreamFinished: {
                const f = {};
                text.trim().split("\n").forEach(l => {
                    const [id, cur, c] = l.split("\t");
                    if (id)
                        f[id] = { current: cur || "", candidates: (c || "").split(",").filter(x => x && !x.startsWith("shani-shell")) };
                });
                page.found = f;
            }
        }
    }
    Process { id: set; onExited: page.refresh() }
    function choose(kind, desktop) {
        set.command = ["sh", "-c", 'd="$1"; shift; for t in "$@"; do gio mime "$t" "$d" >/dev/null || exit 1; done', "sh", desktop].concat(kind.types);
        set.running = true;
        open = "";
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Default apps") }
    Repeater {
        model: page.kinds
        ColumnLayout {
            id: kindRow
            required property var modelData
            readonly property var info: page.found[modelData.id] || { current: "", candidates: [] }
            Layout.fillWidth: true
            spacing: 2
            ListRow {
                Layout.fillWidth: true
                icon: kindRow.modelData.icon
                title: kindRow.modelData.label
                subtitle: kindRow.info.current ? page.nameOf(kindRow.info.current) : (kindRow.info.candidates.length ? "Not set — choose one" : "No app installed for this")
                trailing: kindRow.info.candidates.length > 1 ? "›" : ""
                onClicked: page.open = page.open === kindRow.modelData.id ? "" : kindRow.modelData.id
            }
            Repeater {
                model: page.open === kindRow.modelData.id ? kindRow.info.candidates : []
                ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 28
                    icon: { const e = page.entry(modelData); return e && e.icon ? e.icon : "application-x-executable"; }
                    title: page.nameOf(modelData)
                    selected: modelData === kindRow.info.current
                    onClicked: page.choose(kindRow.modelData, modelData)
                }
            }
        }
    }

    // ---- how an app starts (Services/Launch): its graphics card, environment
    // variables and arguments - what a game or a GPU-hungry tool needs set
    // before it starts, kept per app
    SectionTitle { Layout.fillWidth: true; text: Tr.t("How an app starts") }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Gpu.hasChoice
            ? Tr.t("This computer has two graphics cards. Apps that ask for the faster one get it on their own; here any app can be set to it, and given its own settings.")
            : Tr.t("Give an app its own settings when it starts - environment variables (MANGOHUD=1, for example) and extra arguments.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    property string launchApp: ""
    readonly property var launchOpts: launchApp ? Launch.options(launchApp) : ({})
    function setLaunch(key, value) {
        const o = Object.assign({}, Launch.options(launchApp));
        o[key] = value;
        Launch.setOptions(launchApp, o);
    }
    // the apps that already have their own
    Flow {
        Layout.fillWidth: true
        spacing: 6
        visible: Object.keys(page.d.appLaunch || {}).length > 0
        Repeater {
            model: Object.keys(page.d.appLaunch || {})
            Choice {
                required property string modelData
                text: page.nameOf(modelData)
                selected: page.launchApp === modelData
                onClicked: page.launchApp = modelData
            }
        }
    }
    AppPicker {
        Layout.fillWidth: true
        label: Tr.t("App")
        value: page.launchApp
        onPicked: id => page.launchApp = id
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.launchApp !== ""
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            visible: Gpu.hasChoice
            spacing: 6
            Text { text: Tr.t("Graphics card"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 120 }
            Repeater {
                model: [{ id: "", label: Tr.t("As the app asks") }, { id: "discrete", label: Gpu.other ? Gpu.other.name.split(" ").slice(0, 3).join(" ") : Tr.t("The faster one") }, { id: "default", label: Tr.t("The default one") }]
                Choice {
                    required property var modelData
                    text: modelData.label
                    selected: (page.launchOpts.gpu || "") === modelData.id
                    onClicked: page.setLaunch("gpu", modelData.id)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: Tr.t("Environment"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 120 }
            TextField {
                Layout.fillWidth: true
                placeholder: page.launchOpts.env || Tr.t("NAME=value, space between - Enter to keep")
                onAccepted: { page.setLaunch("env", text.trim()); text = ""; }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: Tr.t("Arguments"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale; Layout.preferredWidth: 120 }
            TextField {
                Layout.fillWidth: true
                placeholder: page.launchOpts.args || Tr.t("added after the app's own - Enter to keep")
                onAccepted: { page.setLaunch("args", text.trim()); text = ""; }
            }
        }
        RowLayout {
            spacing: 8
            Button { text: Tr.t("Start it now"); kind: "primary"; onClicked: Launch.app(page.launchApp) }
            Button { text: Tr.t("Back to how it came"); onClicked: { Launch.setOptions(page.launchApp, null); } }
        }
    }
}
