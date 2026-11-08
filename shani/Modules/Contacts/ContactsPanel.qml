// Contacts: Shani Link's address book as a shell panel — the vCard files in
// $XDG_DATA_HOME/shani-link/contacts/, through Services/Contacts.qml
// (bridge/contacts.py). List, live search, add / edit / delete (name, phone,
// email), click-to-copy, "Call" via Shani Link's dial pad, and vCard import
// from a file. No Evolution Data Server, no EDS/EBook bindings.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Common
import qs.Services

PanelWindow {
    id: win
    visible: Ui.contacts && !Lock.locked
    screen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-contacts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurRegion : null
    Region { id: blurRegion; item: card; radius: Theme.radiusLarge }

    onVisibleChanged: if (visible) Contacts.refresh()
    Component.onCompleted: if (visible) Contacts.refresh()

    // ---- add / edit / delete form ------------------------------------------------
    property bool editor: false
    property var editingContact: null   // the contact being edited, null = new
    property string formError: ""

    function openEditor(contact) {
        editingContact = contact || null;
        formError = "";
        if (contact) {
            fName.text = contact.name || "";
            fPhone.text = contact.phone || "";
            fEmail.text = contact.email || "";
        } else {
            fName.text = "";
            fPhone.text = "";
            fEmail.text = "";
        }
        editor = true;
    }
    function closeEditor() { editor = false; formError = ""; }
    function saveEditor() {
        const name = fName.text.trim();
        if (name === "") {
            formError = Tr.t("A contact needs a name");
            return;
        }
        if (editingContact && editingContact.uid)
            Contacts.editContact(editingContact.uid, name, fPhone.text.trim(), fEmail.text.trim());
        else
            Contacts.addContact(name, fPhone.text.trim(), fEmail.text.trim());
        closeEditor();
    }
    function deleteEditor() {
        if (!editingContact)
            return;
        Contacts.deleteContact(editingContact.uid);
        closeEditor();
    }
    function copyPhone(contact) { Contacts.copyPhone(contact); }
    function copyEmail(contact) { Contacts.copyEmail(contact); }
    function callNumber(number) { Contacts.callNumber(number); }
    function textNumber(number) { Contacts.textNumber(number); }
    function importVCard(path) {
        if (!path)
            return;
        Contacts.importVCard(path);
    }

    // made on first use: a native dialog is the desktop portal's, and made
    // with every picker it held the whole shell while D-Bus waited for it
    Loader {
        id: vcardDlg
        active: false
        function open() { active = true; item.open(); }
        sourceComponent: FileDialog {
            title: Tr.t("Import a vCard file")
            nameFilters: [Tr.t("vCard files") + " (*.vcf *.vcard)", Tr.t("All files") + " (*)"]
            onAccepted: win.importVCard(selectedFile.toString().replace(/^file:\/\//, ""))
        }
    }

    MouseArea { anchors.fill: parent; onClicked: { if (win.editor) win.closeEditor(); else Ui.contacts = false; } }
    Item { anchors.fill: parent; focus: win.visible; Keys.onEscapePressed: { if (win.editor) win.closeEditor(); else Ui.contacts = false; } }

    Glass {
        id: card
        anchors.centerIn: parent
        width: Math.min(600, parent.width - 40)
        height: Math.min(600, parent.height - 80)
        strong: true
        radius: Theme.radiusLarge

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SectionTitle {
                    Layout.fillWidth: true
                    text: Tr.t("Contacts")
                }
                Text {
                    text: Contacts.contacts.length ? Tr.t("%1 contacts", Contacts.contacts.length) : ""
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * Theme.fontScale
                }
                IconButton {
                    icon: "view-refresh"
                    size: 28
                    tip: Tr.t("Refresh")
                    onClicked: Contacts.refresh()
                }
                IconButton {
                    icon: "window-close"
                    size: 28
                    tip: Tr.t("Close")
                    onClicked: Ui.contacts = false
                }
            }

            TextField {
                id: searchField
                visible: !win.editor
                Layout.fillWidth: true
                placeholder: Tr.t("Search contacts — name, number or email")
                label: Tr.t("Search contacts")
                onTextChanged: { if (text !== Contacts.query) Contacts.search(text); }
            }
            Connections { target: Contacts; function onQueryChanged() { if (Contacts.query !== searchField.text) searchField.text = Contacts.query; } }

            RowLayout {
                visible: !win.editor
                Layout.fillWidth: true
                spacing: 8
                Button {
                    text: Tr.t("New contact")
                    kind: "primary"
                    onClicked: win.openEditor(null)
                }
                Button {
                    text: Tr.t("Import vCard…")
                    onClicked: vcardDlg.open()
                }
                Text {
                    Layout.fillWidth: true
                    visible: Contacts.error !== ""
                    text: Contacts.error
                    color: Theme.danger
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
            }

            // ---- the list ----------------------------------------------------------
            ListView {
                id: list
                visible: !win.editor
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: Contacts.contacts
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 104
                    radius: 10
                    color: rowHover.containsMouse ? Theme.hover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: row.modelData.name
                    Accessible.description: [row.modelData.phone, row.modelData.email].filter(s => s).join(", ")
                    Accessible.onPressAction: win.openEditor(row.modelData)

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.openEditor(row.modelData)
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 13 * Theme.fontScale
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: row.modelData.phone !== ""
                            text: row.modelData.phone
                            color: Theme.accent
                            elide: Text.ElideRight
                            font.family: Theme.mono
                            font.pixelSize: 11 * Theme.fontScale
                            Accessible.role: Accessible.Button
                            Accessible.name: Tr.t("Copy phone number")
                            Accessible.onPressAction: win.copyPhone(row.modelData)
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.copyPhone(row.modelData)
                            }
                            KeyFocus {
                                name: Tr.t("Copy phone number")
                                onActivated: win.copyPhone(row.modelData)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: row.modelData.email !== ""
                            text: row.modelData.email
                            color: Theme.dim
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11 * Theme.fontScale
                            Accessible.role: Accessible.Button
                            Accessible.name: Tr.t("Copy email address")
                            Accessible.onPressAction: win.copyEmail(row.modelData)
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.copyEmail(row.modelData)
                            }
                            KeyFocus {
                                name: Tr.t("Copy email address")
                                onActivated: win.copyEmail(row.modelData)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Button {
                                visible: row.modelData.phone !== ""
                                text: Tr.t("Call")
                                onClicked: win.callNumber(row.modelData.phone)
                            }
                            Button {
                                visible: row.modelData.phone !== ""
                                text: Tr.t("Text")
                                onClicked: win.textNumber(row.modelData.phone)
                            }
                            Button {
                                text: Tr.t("Edit")
                                onClicked: win.openEditor(row.modelData)
                            }
                            Button {
                                text: Tr.t("Delete")
                                kind: "danger"
                                onClicked: Contacts.deleteContact(row.modelData.uid)
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                    KeyFocus {
                        name: row.modelData.name
                        onActivated: win.openEditor(row.modelData)
                    }
                }
            }

            EmptyState {
                visible: !win.editor && Contacts.loaded && Contacts.contacts.length === 0
                icon: "system-users"
                title: Contacts.query !== "" ? Tr.t("No matches") : Tr.t("No contacts yet")
                subtitle: Contacts.query !== "" ? Tr.t("Try another search") : Tr.t("Add a contact, or import a vCard file")
                actionText: Tr.t("New contact")
                onAction: win.openEditor(null)
            }

            // ---- add / edit form ---------------------------------------------------
            ColumnLayout {
                visible: win.editor
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: win.editingContact ? Tr.t("Edit contact") : Tr.t("New contact")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                TextField {
                    id: fName
                    Layout.fillWidth: true
                    placeholder: Tr.t("Name")
                    label: Tr.t("Name")
                    onAccepted: win.saveEditor()
                }
                TextField {
                    id: fPhone
                    Layout.fillWidth: true
                    placeholder: Tr.t("Phone")
                    label: Tr.t("Phone")
                    onAccepted: win.saveEditor()
                }
                TextField {
                    id: fEmail
                    Layout.fillWidth: true
                    placeholder: Tr.t("Email")
                    label: Tr.t("Email")
                    onAccepted: win.saveEditor()
                }
                Text {
                    visible: win.formError !== ""
                    Layout.fillWidth: true
                    text: win.formError
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: 11 * Theme.fontScale
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button { Layout.fillWidth: true; text: Tr.t("Save"); kind: "primary"; onClicked: win.saveEditor() }
                    Button { Layout.fillWidth: true; text: Tr.t("Cancel"); onClicked: win.closeEditor() }
                    Button { visible: win.editingContact !== null; text: Tr.t("Delete"); kind: "danger"; onClicked: win.deleteEditor() }
                }
            }

            Text {
                Layout.fillWidth: true
                text: win.editor ? Tr.t("Esc closes the form") : Tr.t("Click a number or email to copy it · Call hands the number to Shani Link's dial pad (Modem.callNumber, tel:) and nothing is dialled until you confirm in Shani Link · Esc closes")
                color: Theme.faint
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 10 * Theme.fontScale
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: { if (win.editor) win.closeEditor(); else Ui.contacts = false; } }
    Shortcut { sequence: "Ctrl+R"; onActivated: Contacts.refresh() }
}
