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
                page.enrolled = (text.match(/#\d+:\s*(\S+)/g) || []).map(x => x.replace(/#\d+:\s*/, "").replace(/-/g, " "));
            }
        }
    }
    Process {
        id: enroll
        command: ["fprintd-enroll", "-f", "right-index-finger"]
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
    Process { id: forget; command: ["fprintd-delete", page.user]; onExited: fingers.running = true }
    onActiveChanged: if (active) refresh()

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

    SectionTitle { Layout.fillWidth: true; text: "Your account" }
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

    Text { text: "Picture"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
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
        text: "Put a picture in Pictures to choose it here."
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
    SectionTitle { Layout.fillWidth: true; text: "Fingerprint"; visible: page.hasReader }
    Text {
        Layout.fillWidth: true
        visible: page.hasReader
        text: page.enrollState === "touch" ? "Touch the reader with your right index finger."
            : page.enrollState === "again" ? "Lift it and touch again — " + page.stages + " done."
            : page.enrollState === "done" ? "Your fingerprint is saved. It unlocks the lock screen and approves admin requests where they allow it."
            : page.enrollState.startsWith("failed") ? "That did not work (" + page.enrollState.slice(8) + "). Try again."
            : page.enrolled.length ? "Enrolled: " + page.enrolled.join(", ") : "No fingerprint saved."
        color: page.enrollState.startsWith("failed") ? Theme.danger : Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12 * Theme.fontScale
    }
    RowLayout {
        visible: page.hasReader
        spacing: 6
        Button { text: enroll.running ? "Enrolling…" : "Add a fingerprint"; enabled: !enroll.running; onClicked: page.startEnroll() }
        Button { visible: page.enrolled.length > 0 && !enroll.running; kind: "danger"; text: "Remove fingerprints"; onClicked: forget.running = true }
    }

    Button {
        text: "Change password…"
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
