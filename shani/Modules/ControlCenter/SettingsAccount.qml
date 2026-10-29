// Settings > Your account: the picture (~/.face — the lock screen's — and
// AccountsService's, which the login screen reads, when it is installed), the
// name others see, and the password. Names and pictures go through
// AccountsService (no password asked for your own account); without it, and
// for the password always, `chfn` / `passwd` run in a terminal, where they ask.
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
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string home: Quickshell.env("HOME") || ""
    property string realName: ""
    property bool accounts: false         // AccountsService on the system bus
    property string accountPath: ""
    property var pictures: []
    property string note: ""

    function refresh() {
        who.running = true;
        pics.running = true;
        fingers.running = true;
    }

    // ---- fingerprints (fprintd): what is enrolled, enrolling one, removing them ----
    property bool hasReader: false
    property var enrolled: []
    property string enrollState: ""        // "", "touch", "again", "done", "failed: …"
    property int stages: 0
    Process {
        id: fingers
        command: ["sh", "-c", 'command -v fprintd-list >/dev/null && fprintd-list "$1" 2>&1', "sh", page.user]
        stdout: StdioCollector {
            onStreamFinished: {
                page.hasReader = text.indexOf("Device at") >= 0;
                page.enrolled = (text.match(/#\d+:\s*(\S+)/g) || []).map(x => x.replace(/#\d+:\s*/, ""));
            }
        }
    }
    Process {
        id: enroll
        command: ["fprintd-enroll", "-f", page.finger]
        stdout: SplitParser {
            onRead: line => {
                if (/enroll-stage-passed/.test(line)) { page.stages++; page.enrollState = "again"; }
                else if (/enroll-retry|enroll-swipe-too-short|enroll-finger-not-centered|enroll-remove-and-retry/.test(line)) page.enrollState = "again";
                else if (/enroll-completed/.test(line)) page.enrollState = "done";
                else if (/enroll-(failed|data-full|disconnected|unknown-error)/.test(line)) page.enrollState = "failed: " + line.replace(/.*enroll-/, "");
            }
        }
        onExited: fingers.running = true
    }
    function startEnroll() { stages = 0; enrollState = "touch"; enroll.running = true; }
    // one finger (fprintd-delete -f), or all of them
    function forgetFinger(f) { forget.command = f ? ["fprintd-delete", "-f", f, page.user] : ["fprintd-delete", page.user]; forget.running = true; }
    Process { id: forget; onExited: fingers.running = true }
    // fprintd's ten names (EnrollStart refuses anything else); the picker offers those not saved yet
    readonly property var fingerNames: ["right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
        "right-middle-finger", "left-middle-finger", "right-ring-finger", "left-ring-finger", "right-little-finger", "left-little-finger"]
    property string finger: "right-index-finger"
    readonly property var unsaved: fingerNames.filter(f => enrolled.indexOf(f) < 0)
    onUnsavedChanged: if (unsaved.indexOf(finger) < 0 && unsaved.length) finger = unsaved[0]
    function fingerLabel(f) { return Tr.t(f.replace(/-finger$/, "").replace(/-/g, " ").replace(/^./, c => c.toUpperCase())); }
    // fprintd's usual stage count; the bar is a guide, "done" comes from fprintd
    readonly property int stagesNeeded: 5
    onActiveChanged: if (active) refresh()
    // made already active (a Settings category is a Loader): load now too
    Component.onCompleted: if (active) refresh()

    Process {
        id: who
        command: ["sh", "-c", 'getent passwd "$1" | cut -d: -f5 | cut -d, -f1
            busctl call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts FindUserByName s "$1" 2>/dev/null | cut -d" " -f2 | tr -d \\"', "sh", page.user]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                page.realName = (l[0] || "").trim();
                page.accountPath = (l[1] || "").trim();
                page.accounts = page.accountPath.startsWith("/");
            }
        }
    }
    // pictures to choose from: the system's faces, then the person's own
    Process {
        id: pics
        command: ["sh", "-c", 'find /usr/share/pixmaps/faces "$HOME/Pictures" -maxdepth 2 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) 2>/dev/null | grep -v "/Screenshots/" | head -24']
        stdout: StdioCollector { onStreamFinished: page.pictures = text.trim().split("\n").filter(x => x) }
    }
    Process {
        id: act
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            page.note = code === 0 ? "" : (actErr.text.trim().split("\n").pop() || "not changed");
            Ui.faceRev++;
            who.running = true;
        }
    }
    function setPicture(path) {
        // a square copy: the lock screen reads ~/.face; AccountsService keeps its own copy
        act.command = ["sh", "-c", 'cp -f "$1" "$HOME/.face" && chmod 644 "$HOME/.face" && { [ -z "$2" ] || busctl call org.freedesktop.Accounts "$2" org.freedesktop.Accounts.User SetIconFile s "$HOME/.face"; }',
                       "sh", path, page.accounts ? page.accountPath : ""];
        act.running = true;
    }
    function setName(name) {
        if (page.accounts) {
            act.command = ["busctl", "call", "org.freedesktop.Accounts", page.accountPath, "org.freedesktop.Accounts.User", "SetRealName", "s", name];
            act.running = true;
        } else {
            Ui.closeAll();
            Quickshell.execDetached([Settings.data.terminal, "-e", "sh", "-c", 'chfn -f "$1"; echo; read -p "Done — press Enter to close." x', "sh", name]);
        }
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Your account") }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Avatar { size: 64 }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: page.realName || page.user; color: Theme.text; font.family: Theme.font; font.pixelSize: 17 * Theme.fontScale; font.weight: Font.DemiBold }
            Text { text: page.user; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11 * Theme.fontScale }
        }
    }

    Text { text: Tr.t("Picture"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: page.pictures
            Image {
                required property string modelData
                width: 48
                height: 48
                source: "file://" + modelData
                sourceSize: Qt.size(96, 96)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                Accessible.role: Accessible.Button
                Accessible.name: "Use " + modelData.split("/").pop()
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.setPicture(parent.modelData) }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.pictures.length === 0
        text: Tr.t("Put a picture in Pictures to choose it here.")
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }

    TextField {
        Layout.fillWidth: true
        placeholder: "Your name, as others see it — " + (page.realName || page.user)
        onAccepted: {
            const n = text.trim();
            if (n !== "" && n.indexOf(":") < 0 && n.indexOf(",") < 0)
                page.setName(n);
            text = "";
        }
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Fingerprint"); visible: page.hasReader }
    Text {
        Layout.fillWidth: true
        visible: page.hasReader
        text: page.enrollState === "touch" ? Tr.t("Touch the reader with your %1.", page.fingerLabel(page.finger).toLowerCase())
            : page.enrollState === "again" ? Tr.t("Lift it and touch again — %1 done.", page.stages)
            : page.enrollState === "done" ? Tr.t("Saved. It unlocks the lock screen and approves admin requests where they allow it.")
            : page.enrollState.startsWith("failed") ? Tr.t("That did not work (%1). Try again.", page.enrollState.slice(8))
            : page.enrolled.length ? "" : Tr.t("No fingerprint saved.")
        color: page.enrollState.startsWith("failed") ? Theme.danger : Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    Rectangle {      // the scans so far
        visible: enroll.running
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: Theme.hover
        Rectangle { width: parent.width * Math.min(1, page.stages / page.stagesNeeded); height: parent.height; radius: 3; color: Theme.accent }
    }
    // saved fingers, each removable
    Repeater {
        model: page.hasReader ? page.enrolled : []
        RowLayout {
            required property string modelData
            Layout.fillWidth: true
            Icon { name: "auth-fingerprint"; size: 18; color: Theme.accent }
            Text { Layout.fillWidth: true; text: page.fingerLabel(modelData); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 * Theme.fontScale }
            IconButton { icon: "edit-delete"; tip: Tr.t("Remove"); Accessible.name: Tr.t("Remove %1", page.fingerLabel(modelData)); onClicked: page.forgetFinger(modelData) }
        }
    }
    Flow {
        visible: page.hasReader && !enroll.running && page.unsaved.length > 0
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: page.unsaved
            Choice { required property string modelData; text: page.fingerLabel(modelData); selected: page.finger === modelData; onClicked: page.finger = modelData }
        }
    }
    RowLayout {
        visible: page.hasReader
        spacing: 6
        Button { text: enroll.running ? Tr.t("Enrolling…") : Tr.t("Add %1", page.fingerLabel(page.finger).toLowerCase()); enabled: !enroll.running && page.unsaved.length > 0; onClicked: page.startEnroll() }
        Button { visible: enroll.running; text: Tr.t("Cancel"); onClicked: enroll.running = false }
        Button { visible: page.enrolled.length > 1 && !enroll.running; kind: "danger"; text: Tr.t("Remove all"); onClicked: page.forgetFinger("") }
    }

    Button {
        text: Tr.t("Change password…")
        onClicked: {
            Ui.closeAll();
            Quickshell.execDetached([Settings.data.terminal, "-e", "sh", "-c", 'passwd; echo; read -p "Press Enter to close." x']);
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.danger
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
