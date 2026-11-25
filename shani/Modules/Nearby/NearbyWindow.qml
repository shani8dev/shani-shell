// Nearby: send files to a phone or computer on the same Wi-Fi, and receive
// from one - anything running LocalSend (Android, iPhone, Windows, Mac,
// Linux), with no pairing. Pick the files, click the device. To be sent to,
// turn on "Visible": it lasts until it is turned off or the computer restarts,
// and every transfer is asked first. (Services/Nearby, bridge/nearby.py)
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Nearby Share"
    visible: Ui.nearby
    onGone: Ui.nearby = false
    implicitWidth: Theme.px(560)
    implicitHeight: Theme.px(660)
    onVisibleChanged: if (visible) Nearby.scan()
    Component.onCompleted: Nearby.scan()

    function pick() {
        FilePicker.open({ mode: "open", multiple: true, title: Tr.t("Files to send"),
                          onPicked: paths => { if (paths.length) Nearby.pending = paths; } });
    }
    function icon(t) { return t === "mobile" ? "phone" : t === "web" ? "web-browser" : t === "server" ? "network-server" : "computer"; }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Ui.nearby = false

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.px(10)

            // ---- asked: someone wants to send ----
            Repeater {
                model: Nearby.offers
                Rectangle {
                    id: offerBox
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: offerCol.implicitHeight + 20
                    radius: Theme.radiusSmall
                    color: Theme.accentSoft
                    border.width: 1
                    border.color: Theme.accentLine
                    ColumnLayout {
                        id: offerCol
                        anchors { fill: parent; margins: Theme.px(10) }
                        spacing: Theme.px(6)
                        Text { Layout.fillWidth: true; text: Tr.t("%1 wants to send you").arg(offerBox.modelData.from); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: offerBox.modelData.files.map(f => f.name + " (" + Nearby.human(f.size) + ")").join(", ")
                            color: Theme.dim; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: Theme.px(12) * Theme.fontScale
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            Button { text: Tr.t("Decline"); onClicked: Nearby.answer(offerBox.modelData.session, false) }
                            Button { kind: "primary"; text: Tr.t("Accept"); onClicked: Nearby.answer(offerBox.modelData.session, true) }
                        }
                    }
                }
            }

            // ---- what to send ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Icon { name: "document-send"; size: Theme.px(20); color: Theme.dim }
                Text {
                    Layout.fillWidth: true
                    text: Nearby.pending.length === 0 ? Tr.t("Choose what to send, then a device")
                        : Nearby.pending.length === 1 ? Nearby.pending[0].split("/").pop()
                        : Tr.t("%1 files").arg(Nearby.pending.length)
                    color: Nearby.pending.length ? Theme.text : Theme.dim
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: Theme.px(13) * Theme.fontScale
                }
                Button { text: Nearby.pending.length ? Tr.t("Change…") : Tr.t("Choose files…"); onClicked: win.pick() }
            }

            RowLayout {
                Layout.fillWidth: true
                SectionTitle { Layout.fillWidth: true; text: Tr.t("Devices nearby") }
                BusyNote { visible: Nearby.scanning; note: Tr.t("Looking…") }
                IconButton { size: Theme.px(28); icon: "view-refresh"; tip: Tr.t("Look again"); enabled: !Nearby.scanning; onClicked: Nearby.scan() }
            }
            ListView {
                reuseItems: true
                cacheBuffer: 400
                id: devList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.px(4)
                boundsBehavior: Flickable.StopAtBounds
                model: Nearby.devices
                delegate: ListRow {
                    required property var modelData
                    width: devList.width
                    icon: win.icon(modelData.deviceType)
                    title: modelData.alias
                    subtitle: Nearby.pending.length ? [modelData.deviceModel, modelData.ip].filter(x => x).join("  ·  ") : Tr.t("Click to choose files first")
                    trailing: Nearby.pending.length ? Tr.t("Send") : ""
                    onClicked: Nearby.pending.length ? Nearby.sendTo(modelData.fingerprint) : win.pick()
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: devList.count === 0 && !Nearby.scanning
                    icon: "network-wireless"
                    title: Tr.t("No one nearby yet")
                    subtitle: !Nearby.visible_ ? Tr.t("Turn on \"Visible to devices nearby\" below so others can find you")
                                              : Tr.t("Open LocalSend on the phone or computer, on the same Wi-Fi")
                }
            }

            // ---- what is going on ----
            Repeater {
                model: Object.keys(Nearby.transfers).map(k => Object.assign({ session: k }, Nearby.transfers[k])).slice(-3)
                RowLayout {
                    id: tr
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(8)
                    Icon { name: tr.modelData.direction === "send" ? "go-up" : "go-down"; size: Theme.px(16); color: tr.modelData.state === "failed" ? Theme.danger : Theme.dim }
                    Text {
                        Layout.fillWidth: true
                        text: tr.modelData.state === "failed" ? Tr.t("Not sent: %1").arg(tr.modelData.error)
                            : tr.modelData.state === "done" ? (tr.modelData.direction === "send" ? Tr.t("Sent") : Tr.t("Received into Downloads/Nearby"))
                            : tr.modelData.direction === "receive"
                                ? (tr.modelData.total ? Tr.t("Receiving: %1%").arg(Math.round(100 * tr.modelData.done / tr.modelData.total)) : Tr.t("Receiving…"))
                                : (tr.modelData.total ? Tr.t("Sending to %1: %2%").arg(tr.modelData.alias || "").arg(Math.round(100 * tr.modelData.done / tr.modelData.total)) : Tr.t("Waiting for them to accept…"))
                        color: tr.modelData.state === "failed" ? Theme.danger : Theme.dim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.px(12) * Theme.fontScale
                    }
                    Button {
                        visible: tr.modelData.state === "done" && tr.modelData.direction === "receive" && (tr.modelData.files || []).length > 0
                        flat: true
                        text: Tr.t("Show")
                        onClicked: Files.show(tr.modelData.files[0].replace(/\/[^/]*$/, ""))
                    }
                    IconButton {
                        visible: !["done", "failed"].includes(tr.modelData.state)
                        icon: "process-stop"
                        size: Theme.px(22)
                        tip: Tr.t("Cancel transfer")
                        onClicked: Nearby.cancel(tr.modelData.session)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: Nearby.note !== ""
                spacing: Theme.px(6)
                Text { Layout.fillWidth: true; text: Nearby.note; color: Theme.danger; wrapMode: Text.Wrap; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                IconButton { size: Theme.px(22); icon: "window-close"; tip: Tr.t("Dismiss"); onClicked: Nearby.note = "" }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
            SwitchRow {
                Layout.fillWidth: true
                text: Tr.t("Visible to devices nearby as %1", Nearby.me || "")
                hint: Tr.t("Lets them send to this computer; each transfer is asked. Until you turn it off or restart.")
                checked: Nearby.visible_
                onToggled: on => Nearby.setVisible(on)
            }
        }
    }
}
