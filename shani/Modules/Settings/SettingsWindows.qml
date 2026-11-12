// Settings > Windows: how niri lays windows out (InputConfig writes it into
// the shell's niri include): the gaps between them, the focus ring, how wide a
// new window opens, whether focus follows the pointer, and animations.
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: 12
    readonly property var d: Settings.data

    SectionTitle { Layout.fillWidth: true; text: Tr.t("Windows") }
    Picks {
        label: Tr.t("Gaps between windows")
        options: [{ label: Tr.t("None"), value: 0 }, { label: Tr.t("Small"), value: 6 }, { label: Tr.t("Medium"), value: 12 }, { label: Tr.t("Large"), value: 20 }]
        current: page.d.winGaps
        onPicked: v => page.d.winGaps = v
    }
    Picks {
        label: Tr.t("A new window opens")
        options: [{ label: Tr.t("A third"), value: 0.33333 }, { label: Tr.t("Half"), value: 0.5 }, { label: Tr.t("Two thirds"), value: 0.66667 }, { label: Tr.t("Full width"), value: 1 }]
        current: page.d.winDefaultWidth
        onPicked: v => page.d.winDefaultWidth = v
    }
    Picks {
        label: Tr.t("Focus ring")
        options: [{ label: Tr.t("Off"), value: 0 }, { label: Tr.t("Thin"), value: 2 }, { label: Tr.t("Thick"), value: 4 }]
        current: page.d.winFocusRing
        onPicked: v => page.d.winFocusRing = v
    }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Focus follows the pointer"); hint: Tr.t("the window under the pointer takes the keyboard"); checked: page.d.winFocusFollowsMouse; onToggled: on => page.d.winFocusFollowsMouse = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("Window animations"); hint: Tr.t("opening, closing and scrolling (Reduce motion turns the shell's own off)"); checked: page.d.winAnimations; onToggled: on => page.d.winAnimations = on }

    // ---- look and motion: Services/WindowLook writes niri's shani-look.kdl -------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Look and motion") }
    Picks {
        label: Tr.t("Windows open and close")
        enabled: page.d.winAnimations && !page.d.reduceMotion
        options: [{ label: Tr.t("Glide"), value: "glide" }, { label: Tr.t("Pop"), value: "pop" }, { label: Tr.t("Dissolve"), value: "dissolve" }, { label: Tr.t("Plain"), value: "plain" }]
        current: page.d.winMotion
        onPicked: v => page.d.winMotion = v
    }
    Text {
        Layout.fillWidth: true
        text: !page.d.winAnimations || page.d.reduceMotion ? Tr.t("Animations are off, so windows simply appear.")
            : ({ glide: Tr.t("Rises into place as it fades in; sinks away when closed."),
                 pop: Tr.t("Springs open with a little bounce; shrinks away quickly."),
                 dissolve: Tr.t("Gathers in small grains, with your accent colour along the edge."),
                 plain: Tr.t("niri's own: a quick fade and zoom.") })[page.d.winMotion] || ""
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    Picks {
        label: Tr.t("Speed")
        enabled: page.d.winAnimations && !page.d.reduceMotion
        options: [{ label: Tr.t("Brisk"), value: 0.7 }, { label: Tr.t("Normal"), value: 1.0 }, { label: Tr.t("Relaxed"), value: 1.5 }]
        current: page.d.winSpeed
        onPicked: v => page.d.winSpeed = v
    }
    Picks {
        label: Tr.t("Shadow")
        options: [{ label: Tr.t("None"), value: "off" }, { label: Tr.t("Soft"), value: "soft" }, { label: Tr.t("Deep"), value: "deep" }]
        current: page.d.winShadow
        onPicked: v => page.d.winShadow = v
    }
    Picks {
        label: Tr.t("Corners")
        options: [{ label: Tr.t("Square"), value: 0 }, { label: Tr.t("Slight"), value: 8 }, { label: Tr.t("Rounded"), value: 12 }, { label: Tr.t("Round"), value: 18 }]
        current: page.d.winCorners
        onPicked: v => page.d.winCorners = v
    }
    Picks {
        label: Tr.t("Frosted glass")
        options: [{ label: Tr.t("Light"), value: "light" }, { label: Tr.t("Medium"), value: "medium" }, { label: Tr.t("Strong"), value: "strong" }]
        current: page.d.blurStrength
        onPicked: v => page.d.blurStrength = v
    }

    // ---- per-app rules: written to the shell's niri include (WindowRules) -------------
    function setRule(i, patch) {
        const rules = Array.from(page.d.windowRules || []);
        rules[i] = Object.assign({}, rules[i] || { app: "", float: false, workspace: "", width: 0 }, patch);
        page.d.windowRules = rules;
    }
    function popRule(i) {
        const rules = Array.from(page.d.windowRules || []);
        rules.splice(i, 1);
        page.d.windowRules = rules;
    }
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Per-app rules") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("How an app's windows open: floating or tiled, on which workspace (one you named in niri's config), how wide. Type the app id (as `niri msg windows` shows it), then pick. Nothing set means niri's usual tiling.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
    Repeater {
        model: Array.from(page.d.windowRules || [])
        ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                AppPicker {
                    Layout.fillWidth: true
                    label: Tr.t("App")
                    value: modelData.app || ""
                    onPicked: id => page.setRule(index, { app: id })
                }
                IconButton { icon: "list-remove"; onClicked: page.popRule(index) }
            }
            Picks {
                label: Tr.t("Opens floating?")
                options: [{ label: Tr.t("Tiled, like the rest"), value: false }, { label: Tr.t("Floating"), value: true }]
                current: !!modelData.float
                onPicked: v => page.setRule(index, { float: v })
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: Tr.t("Opens on workspace"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: ["", "1", "2", "3", "4", "5"]
                        Choice {
                            required property string modelData
                            readonly property string ws: index === undefined ? "" : index
                            text: modelData === "" ? Tr.t("Default") : Tr.t("Workspace ") + modelData
                            selected: (modelData.workspace || "") === modelData
                            onClicked: page.setRule(index, { workspace: modelData })
                        }
                    }
                }
            }
            Picks {
                label: Tr.t("Width")
                options: [{ label: Tr.t("Niri's usual"), value: 0 }, { label: Tr.t("A third"), value: 0.33333 }, { label: Tr.t("Half"), value: 0.5 }, { label: Tr.t("Two thirds"), value: 0.66667 }, { label: Tr.t("Full"), value: 1 }]
                current: modelData.width || 0
                onPicked: v => page.setRule(index, { width: v })
            }
        }
    }
    Button {
        Layout.fillWidth: true
        text: Tr.t("Add a rule for an app")
        onClicked: page.d.windowRules = Array.from(page.d.windowRules || []).concat([{ app: "", float: false, workspace: "", width: 0 }])
    }

    Text {
        Layout.fillWidth: true
        text: Tr.t("Windows sit side by side in columns that scroll; Mod+R cycles a column's width, Mod+F makes it full, Mod+O shows every workspace.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11 * Theme.fontScale
    }
}
