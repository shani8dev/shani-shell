// Models: discover, download, and manage AI models on this computer.
// Shows installed models (ollama, llama.cpp), what fits in available RAM,
// and lets you download new ones. Also connect AI providers (OpenAI,
// Anthropic, Mistral) for cloud models — keys are stored in Passwords.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services

AppWindow {
    id: win
    appName: "Models"
    visible: Ui.models
    onGone: Ui.models = false
    implicitWidth: Theme.px(760)
    implicitHeight: Theme.px(580)

    // tab: "local" (installed models) or "providers" (cloud providers)
    property string tab: "local"
    // name of the model awaiting delete confirmation; "" means no confirm open
    property string pendingRemove: ""
    // provider connection form
    property string connectId: ""
    property string connectKey: ""
    property string connectEndpoint: ""

    onVisibleChanged: if (visible) Models.refresh()

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Ui.models = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(8)

        // ---- header ----
        // the tabs wrap on a phone instead of running off the edge
        Flow {
            Layout.fillWidth: true
            spacing: Theme.px(6)
            // the title is the window's own (AppWindow's header), not repeated here
            Button { text: Tr.t("Local models"); checked: win.tab === "local"; onClicked: win.tab = "local" }
            Button { text: Tr.t("AI providers"); checked: win.tab === "providers"; onClicked: win.tab = "providers" }
            Button { text: Tr.t("Refresh"); flat: true; onClicked: Models.refresh() }
        }

        // ---- system resources bar ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.px(36)
            radius: Theme.radiusSmall
            color: Theme.surface1
            RowLayout {
                anchors { fill: parent; margins: Theme.px(10) }
                spacing: Theme.px(16)
                Text { text: Tr.t("RAM: %1 GB free / %2 GB", Models.ramAvailable.toFixed(1), Models.ramTotal.toFixed(1)); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                Text { visible: Models.vram > 0; text: Tr.t("VRAM: %1 GB", Models.vram.toFixed(1)); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                Text { visible: Models.gpuName !== ""; text: Models.gpuName; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("caption"); elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }

        // ---- local models tab ----
        ColumnLayout {
            visible: win.tab === "local"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            // installed models
            Text {
                text: Tr.t("Installed models")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                font.weight: Font.DemiBold
            }
            ListView {
                id: installedList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                cacheBuffer: 400
                model: Models.installed
                delegate: Rectangle {
                    required property var modelData
                    width: installedList.width
                    height: Theme.px(52)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(10) }
                        spacing: Theme.px(10)
                        Icon { name: "applications-internet"; size: Theme.px(22); color: Theme.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body"); elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.size + " · " + modelData.source; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                        }
                        Text {
                            visible: !Models.fitsInRam(modelData.size)
                            text: Tr.t("Too large for RAM")
                            color: Theme.red
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                        }
                        Button {
                            text: Settings.data.chronoaPreferredModel === modelData.name ? Tr.t("Using") : Tr.t("Use for Chronoa")
                            flat: true
                            checked: Settings.data.chronoaPreferredModel === modelData.name
                            enabled: Settings.data.chronoaPreferredModel !== modelData.name
                            onClicked: Settings.data.chronoaPreferredModel = modelData.name
                        }
                        IconButton {
                            size: Theme.px(26)
                            icon: "user-trash"
                            tip: Tr.t("Remove %1", modelData.name)
                            onClicked: win.pendingRemove = modelData.name
                        }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                EmptyState {
                    anchors.centerIn: parent
                    visible: installedList.count === 0
                    icon: "applications-internet"
                    title: Tr.t("No models installed")
                    subtitle: Tr.t("Download one below, or install ollama")
                }
            }

            // available downloads
            Text {
                text: Tr.t("Available downloads")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                font.weight: Font.DemiBold
            }
            ListView {
                id: availList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(availList.contentItem.children.length * Theme.px(52), Theme.px(280))
                clip: true
                model: Models.available
                delegate: Rectangle {
                    id: availModel
                    required property var modelData
                    width: availList.width
                    height: Theme.px(52)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : "transparent"
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(10) }
                        spacing: Theme.px(10)
                        Icon { name: "download"; size: Theme.px(22); color: Theme.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body"); elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.size + " · " + modelData.description; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small"); elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Text {
                            visible: !Models.fitsInRam(modelData.size)
                            text: Tr.t("May not fit")
                            color: Theme.amber
                            font.family: Theme.font
                            font.pixelSize: Theme.type("caption")
                        }
                        Button {
                            text: Tr.t("Download")
                            kind: "outline"
                            enabled: Models.fitsInRam(modelData.size)
                            onClicked: { Models.download(modelData.name); Settings.data.chronoaPreferredModel = modelData.name; }
                        }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
        }

        // ---- providers tab ----
        ColumnLayout {
            visible: win.tab === "providers"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.px(6)

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Tr.t("Connect cloud AI providers. API keys are stored encrypted in Passwords — they never leave your computer except to the provider you choose.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
            }

            InfoBanner {
                Layout.fillWidth: true
                visible: AIProviders.syncError !== ""
                tone: "error"
                text: AIProviders.syncError
                Accessible.role: Accessible.AlertMessage
                Accessible.name: AIProviders.syncError
            }

            // connected providers
            Repeater {
                model: AIProviders.providers
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: Theme.px(52)
                    radius: Theme.radiusSmall
                    color: Theme.surface1
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(10) }
                        spacing: Theme.px(10)
                        Icon { name: "applications-internet"; size: Theme.px(22); color: Theme.accent }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body"); font.weight: Font.DemiBold }
                            Text { text: modelData.endpoint || "—"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                        }
                        Text { text: Tr.t("Connected"); color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                        Button { text: Tr.t("Disconnect"); kind: "outline"; flat: true; onClicked: AIProviders.disconnect(modelData.id) }
                    }
                }
            }

            // available providers
            Text {
                text: Tr.t("Available providers")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.type("body")
                font.weight: Font.DemiBold
            }
            Repeater {
                model: AIProviders.available.filter(a => !AIProviders.isConnected(a.id))
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: Theme.px(72)
                    radius: Theme.radiusSmall
                    color: rowArea.containsMouse ? Theme.hover : Theme.surface1
                    RowLayout {
                        anchors { fill: parent; margins: Theme.px(10) }
                        spacing: Theme.px(10)
                        Icon { name: "applications-internet"; size: Theme.px(22); color: Theme.dim }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.type("body"); font.weight: Font.DemiBold }
                            Text { text: modelData.endpoint || Tr.t("Enter your endpoint URL"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.type("small") }
                            Text { visible: modelData.docs !== ""; text: modelData.docs; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.type("caption") }
                        }
                        Button { text: Tr.t("Connect…"); kind: "primary"; onClicked: { win.connectId = modelData.id; win.connectKey = ""; win.connectEndpoint = modelData.endpoint || ""; } }
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
        }

        // ---- connect form ----
        Dialog {
            id: connectDialog
            anchors.centerIn: parent
            width: Math.min(win.width * 0.8, Theme.px(420))
            title: Tr.t("Connect %1", (AIProviders.available.find(a => a.id === win.connectId) || {}).name || win.connectId)
            modal: true
            standardButtons: Dialog.No | Dialog.Yes
            visible: win.connectId !== ""
            onAccepted: {
                if (win.connectKey.trim() === "") return; // Connect is disabled until a key is typed
                AIProviders.connect(win.connectId, (AIProviders.available.find(a => a.id === win.connectId) || {}).name, win.connectKey, win.connectEndpoint);
                win.connectId = "";
                win.connectKey = "";       // don't keep the secret live after connecting
                win.connectEndpoint = "";
            }
            onRejected: {                  // No / Cancel / Escape must dismiss, not re-open
                win.connectId = "";
                win.connectKey = "";
                win.connectEndpoint = "";
            }
            Component.onCompleted: {
                const yes = connectDialog.standardButton(Dialog.Yes);
                if (yes) yes.enabled = Qt.binding(() => win.connectKey.trim() !== "");
            }
            contentItem: ColumnLayout {
                spacing: Theme.px(12)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Your API key is stored encrypted in Passwords. It is only sent to the provider you choose.")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                    wrapMode: Text.Wrap
                }
                TextField {
                    Layout.fillWidth: true
                    placeholder: Tr.t("API key")
                    label: Tr.t("API key")
                    secret: true
                    text: win.connectKey
                    onTextChanged: win.connectKey = text
                }
                Text {
                    Layout.fillWidth: true
                    visible: win.connectKey.trim() === ""
                    text: Tr.t("Enter an API key to enable Connect")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.type("small")
                    wrapMode: Text.Wrap
                }
                TextField {
                    Layout.fillWidth: true
                    visible: win.connectId === "custom"
                    placeholder: Tr.t("Endpoint URL")
                    label: Tr.t("Endpoint URL")
                    text: win.connectEndpoint
                    onTextChanged: win.connectEndpoint = text
                }
            }
        }

        // ---- remove confirmation (deleting a model frees disk space for good) ----
        Dialog {
            id: removeConfirm
            anchors.centerIn: parent
            width: Math.min(win.width * 0.8, Theme.px(420))
            title: Tr.t("Remove %1?", win.pendingRemove)
            modal: true
            standardButtons: Dialog.No | Dialog.Yes
            visible: win.pendingRemove !== ""
            onRejected: win.pendingRemove = ""
            onAccepted: {
                const name = win.pendingRemove;
                win.pendingRemove = "";
                // a preference pointing at a deleted model leaves Chronoa naming a
                // model that no longer exists — clear it while it is still known
                if (Settings.data.chronoaPreferredModel === name)
                    Settings.data.chronoaPreferredModel = "";
                Models.remove(name);
            }
            contentItem: Item {
                implicitHeight: removeMessage.implicitHeight
                Text {
                    id: removeMessage
                    width: removeConfirm.availableWidth
                    wrapMode: Text.Wrap
                    text: Tr.t("Remove the downloaded model from this computer? You will need to download it again to use it.")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.type("body")
                }
            }
        }
    }
}
