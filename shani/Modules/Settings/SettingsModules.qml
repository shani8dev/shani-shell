// Settings > Kernel modules: what the kernel has loaded, read-only. Nothing here
// loads or unloads a module; modprobe/rmmod change the running kernel.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
    property bool active: false
    property string query: ""

    onActiveChanged: if (active) KernelModules.refresh()
    Component.onCompleted: if (active) KernelModules.refresh()

    readonly property var shown: {
        const q = page.query.trim().toLowerCase();
        const all = KernelModules.modules || [];
        if (q === "") return all;
        return all.filter(m => String(m.name).toLowerCase().indexOf(q) >= 0
            || (m.usedBy || []).some(d => String(d).toLowerCase().indexOf(q) >= 0));
    }

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Kernel modules") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("%1 modules loaded. Read from /proc/modules; nothing here loads or unloads one.").arg(KernelModules.count)
        color: Theme.dim
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    TextField {
        Layout.fillWidth: true
        placeholder: Tr.t("Filter modules…")
        onTextChanged: page.query = text
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.px(2)
        Repeater {
            model: page.shown
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                interactive: false
                icon: "application-x-addon"
                title: modelData.name
                subtitle: {
                    const deps = (modelData.usedBy || []).length ? Tr.t("used by %1", modelData.usedBy.join(", ")) : Tr.t("no dependents");
                    return Tr.t("%1 KiB", Math.round((modelData.size || 0) / 1024)) + "  ·  " + deps;
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.shown.length === 0 && KernelModules.loaded
        text: Tr.t("No module matches.")
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
