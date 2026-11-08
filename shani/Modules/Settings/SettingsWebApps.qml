import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    property bool active: false
    readonly property var d: Settings.data

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Web apps") }

    Repeater {
        model: d.webApps || []
        delegate: ListRow {
            Layout.fillWidth: true
            icon: modelData.icon || "web-browser"
            title: modelData.title || modelData.name || modelData.url
            subtitle: modelData.url
            trailing: "✕"
            onClicked: {
                const apps = JSON.parse(JSON.stringify(d.webApps || []))
                apps.splice(index, 1)
                d.webApps = apps
            }
        }
    }

    ListRow {
        Layout.fillWidth: true
        icon: "list-add"
        title: Tr.t("Add web app")
        onClicked: addDialog.visible = true
    }

    Item {
        id: addDialog
        visible: false
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? addCol.implicitHeight : 0
        ColumnLayout {
            id: addCol
            anchors.fill: parent
            spacing: 8

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [{ n: "WhatsApp", u: "https://web.whatsapp.com" }, { n: "Gmail", u: "https://mail.google.com" },
                            { n: "YouTube", u: "https://www.youtube.com" }, { n: "YouTube Music", u: "https://music.youtube.com" },
                            { n: "Google Docs", u: "https://docs.google.com" }, { n: "Outlook", u: "https://outlook.live.com" },
                            { n: "Microsoft Teams", u: "https://teams.microsoft.com" }, { n: "Netflix", u: "https://www.netflix.com" },
                            { n: "Claude", u: "https://claude.ai" }, { n: "ChatGPT", u: "https://chatgpt.com" },
                            { n: "X (Twitter)", u: "https://x.com" }, { n: "Instagram", u: "https://www.instagram.com" },
                            { n: "Facebook", u: "https://www.facebook.com" }, { n: "Reddit", u: "https://www.reddit.com" },
                            { n: "Google Maps", u: "https://www.google.com/maps" },
                            { n: "Amazon", u: "https://www.amazon.in" }, { n: "GitHub", u: "https://github.com" },
                            { n: "Wikipedia", u: "https://en.wikipedia.org" },
                            { n: "Perplexity", u: "https://www.perplexity.ai" },
                            { n: "Google Drive", u: "https://drive.google.com" },
                            { n: "Telegram", u: "https://web.telegram.org" }]
                    Choice {
                        required property var modelData
                        text: modelData.n
                        selected: urlInput.text === modelData.u
                        onClicked: { nameInput.text = modelData.n; urlInput.text = modelData.u; }
                    }
                }
            }
            TextField {
                id: nameInput
                Layout.fillWidth: true
                placeholder: Tr.t("Name")
            }
            TextField {
                id: urlInput
                Layout.fillWidth: true
                placeholder: Tr.t("URL (e.g., https://example.com)")
            }
            TextField {
                id: iconInput
                Layout.fillWidth: true
                placeholder: Tr.t("Icon name (optional)")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    text: Tr.t("Cancel")
                    onClicked: { addDialog.visible = false; nameInput.text = ""; urlInput.text = ""; iconInput.text = "" }
                }
                Button {
                    text: Tr.t("Add")
                    onClicked: {
                        if (urlInput.text === "") return
                        const apps = JSON.parse(JSON.stringify(d.webApps || []))
                        apps.push({
                            name: nameInput.text || urlInput.text,
                            title: nameInput.text || urlInput.text,
                            url: urlInput.text,
                            icon: iconInput.text
                        })
                        d.webApps = apps
                        addDialog.visible = false
                        nameInput.text = ""
                        urlInput.text = ""
                        iconInput.text = ""
                    }
                }
            }
        }
    }
}
