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
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: Tr.t("Models")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.px(16) * Theme.fontScale
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
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
                Text { text: Tr.t("RAM: %1 GB free / %2 GB", Models.ramAvailable.toFixed(1), Models.ramTotal.toFixed(1)); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Text { visible: Models.vram > 0; text: Tr.t("VRAM: %1 GB", Models.vram.toFixed(1)); color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                Text { visible: Models.gpuName !== ""; text: Models.gpuName; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(10) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
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
                font.pixelSize: Theme.px(12) * Theme.fontScale
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
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.size + " · " + modelData.source; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                        Text {
                            visible: !Models.fitsInRam(modelData.size)
                            text: Tr.t("Too large for RAM")
                            color: Theme.red
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
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
                            onClicked: Models.remove(modelData.name)
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
                font.pixelSize: Theme.px(12) * Theme.fontScale
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
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.size + " · " + modelData.description; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Text {
                            visible: !Models.fitsInRam(modelData.size)
                            text: Tr.t("May not fit")
                            color: Theme.amber
                            font.family: Theme.font
                            font.pixelSize: Theme.px(10) * Theme.fontScale
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
                font.pixelSize: Theme.px(12) * Theme.fontScale
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
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                            Text { text: modelData.endpoint || "—"; color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        }
                        Text { text: Tr.t("Connected"); color: Theme.accent; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                        Button { text: Tr.t("Disconnect"); kind: "outline"; flat: true; onClicked: AIProviders.disconnect(modelData.id) }
                    }
                }
            }

            // available providers
            Text {
                text: Tr.t("Available providers")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px(12) * Theme.fontScale
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
                            Text { text: modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.px(13) * Theme.fontScale; font.weight: Font.DemiBold }
                            Text { text: modelData.endpoint || Tr.t("Enter your endpoint URL"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.px(11) * Theme.fontScale }
                            Text { visible: modelData.docs !== ""; text: modelData.docs; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.px(9) * Theme.fontScale }
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
                AIProviders.connect(win.connectId, (AIProviders.available.find(a => a.id === win.connectId) || {}).name, win.connectKey, win.connectEndpoint);
                win.connectId = "";
            }
            contentItem: ColumnLayout {
                spacing: Theme.px(12)
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Your API key is stored encrypted in Passwords. It is only sent to the provider you choose.")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.px(12) * Theme.fontScale
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
    }
}