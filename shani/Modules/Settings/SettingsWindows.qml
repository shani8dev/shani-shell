// Settings > Windows: how niri lays windows out (InputConfig writes it into
// the shell's niri include): the gaps between them, the focus ring, how wide a
// new window opens, whether focus follows the pointer, and animations.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Services

ColumnLayout {
    id: page
    spacing: Theme.px(12)
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
    SwitchRow { Layout.fillWidth: true; text: Tr.t("New windows open as tabs"); hint: Tr.t("a column shows one window at a time, with tabs at its side"); checked: page.d.winTabbed; onToggled: on => page.d.winTabbed = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("An empty workspace above the first"); hint: Tr.t("somewhere new is one step up, as well as down"); checked: page.d.winEmptyAbove; onToggled: on => page.d.winEmptyAbove = on }
    SwitchRow { Layout.fillWidth: true; text: Tr.t("A workspace's key twice goes back"); hint: Tr.t("Mod+2 on workspace 2 returns to where you were"); checked: page.d.wsBackAndForth; onToggled: on => page.d.wsBackAndForth = on }
    Picks {
        label: Tr.t("The overview shows workspaces")
        options: [{ label: Tr.t("Small"), value: 0.35 }, { label: Tr.t("Medium"), value: 0.5 }, { label: Tr.t("Large"), value: 0.7 }]
        current: page.d.overviewZoom
        onPicked: v => page.d.overviewZoom = v
    }
    // room windows leave free at each edge (a panel of your own, a notch, a screen's worn edge)
    Repeater {
        model: [{ key: "winStrutLeft", label: Tr.t("Room kept free on the left") }, { key: "winStrutRight", label: Tr.t("Room kept free on the right") },
                { key: "winStrutTop", label: Tr.t("Room kept free at the top") }, { key: "winStrutBottom", label: Tr.t("Room kept free at the bottom") }]
        Picks {
            required property var modelData
            label: modelData.label
            options: [{ label: Tr.t("None"), value: 0 }, { label: Tr.t("A little"), value: 24 }, { label: Tr.t("Some"), value: 64 }, { label: Tr.t("A lot"), value: 128 }]
            current: page.d[modelData.key]
            onPicked: v => page.d[modelData.key] = v
        }
    }
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
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Picks {
        label: Tr.t("Speed")
        enabled: page.d.winAnimations && !page.d.reduceMotion
        options: [{ label: Tr.t("Brisk"), value: 0.7 }, { label: Tr.t("Normal"), value: 1.0 }, { label: Tr.t("Relaxed"), value: 1.5 }]
        current: page.d.winSpeed
        onPicked: v => page.d.winSpeed = v
    }
    // ---- animation presets: .kdl files included before our own block -------------
    Process {
        id: presetLister
        command: ["sh", "-c", 'd="${XDG_CONFIG_HOME:-$HOME/.config}/niri/animations"; [ -d "$d" ] && find "$d" -maxdepth 1 -name "*.kdl" -type f 2>/dev/null | sort']
        stdout: StdioCollector { onStreamFinished: { page.animationPresets = text.trim().split("\n").filter(s => s !== ""); } }
    }
    property var animationPresets: []
    Component.onCompleted: presetLister.running = true
    Picks {
        label: Tr.t("Animation preset")
        enabled: page.d.winAnimations && !page.d.reduceMotion
        options: [{ label: Tr.t("No preset"), value: "" }].concat(page.animationPresets.map(p => ({ label: p.split("/").pop().replace(/\.kdl$/, ""), value: p })))
        current: page.d.winAnimationPreset || ""
        onPicked: v => page.d.winAnimationPreset = v
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
        rules[i] = Object.assign({}, rules[i] || { app: "", title: "", mode: "tiled", workspace: "", output: "", width: 0, height: 0 }, patch);
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
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
    Repeater {
        model: Array.from(page.d.windowRules || [])
        ColumnLayout {
            id: rule
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: Theme.px(4)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                AppPicker {
                    Layout.fillWidth: true
                    label: Tr.t("App")
                    value: modelData.app || ""
                    onPicked: id => page.setRule(index, { app: id })
                }
                IconButton { icon: "list-remove"; tip: Tr.t("Remove"); onClicked: page.popRule(index) }
            }
            Picks {
                label: Tr.t("How it opens")
                options: [
                    { label: Tr.t("Tiled, like the rest"), value: "tiled" },
                    { label: Tr.t("Floating"), value: "floating" },
                    { label: Tr.t("Full screen"), value: "fullscreen" },
                    { label: Tr.t("Maximized"), value: "maximized" },
                    { label: Tr.t("Maximized to edges"), value: "maximized_edges" }
                ]
                current: rule.modelData.mode || (rule.modelData.float ? "floating" : "tiled")
                onPicked: v => page.setRule(index, { mode: v, float: v === "floating" })
            }
            TextField {
                Layout.fillWidth: true
                placeholder: Tr.t("Also match window title (a regular expression)")
                label: Tr.t("Window title")
                text: rule.modelData.title || ""
                onTextChanged: page.setRule(index, { title: text })
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                Text { text: Tr.t("Opens on workspace"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: ["", "1", "2", "3", "4", "5"]
                        Choice {
                            required property string modelData
                            text: modelData === "" ? Tr.t("Default") : Tr.t("Workspace ") + modelData
                            selected: (rule.modelData.workspace || "") === modelData
                            onClicked: page.setRule(index, { workspace: modelData })
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                visible: Displays.outputs.length > 1
                Text { text: Tr.t("Opens on screen"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Choice {
                        text: Tr.t("Any screen")
                        selected: !rule.modelData.output
                        onClicked: page.setRule(index, { output: "" })
                    }
                    Repeater {
                        model: Displays.outputs
                        Choice {
                            required property var modelData
                            text: modelData.label || modelData.name
                            selected: (rule.modelData.output || "") === modelData.name
                            onClicked: page.setRule(index, { output: modelData.name })
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                visible: (rule.modelData.mode || (rule.modelData.float ? "floating" : "tiled")) === "tiled"
                    || (rule.modelData.mode || (rule.modelData.float ? "floating" : "tiled")) === "floating"
                Text { text: Tr.t("Width"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [
                            { label: Tr.t("Niri's usual"), value: 0 },
                            { label: Tr.t("A third"), value: 0.33333 },
                            { label: Tr.t("Half"), value: 0.5 },
                            { label: Tr.t("Two thirds"), value: 0.66667 },
                            { label: Tr.t("Full"), value: 1 }
                        ]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: (rule.modelData.width || 0) === modelData.value
                            onClicked: page.setRule(index, { width: modelData.value })
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(8)
                visible: (rule.modelData.mode || (rule.modelData.float ? "floating" : "tiled")) === "tiled"
                    || (rule.modelData.mode || (rule.modelData.float ? "floating" : "tiled")) === "floating"
                Text { text: Tr.t("Height"); color: Theme.dim; font.family: Theme.font; font.pixelSize: Theme.fontSmall * Theme.fontScale }
                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Repeater {
                        model: [
                            { label: Tr.t("Niri's usual"), value: 0 },
                            { label: Tr.t("A third"), value: 0.33333 },
                            { label: Tr.t("Half"), value: 0.5 },
                            { label: Tr.t("Full"), value: 1 },
                            { label: Tr.t("800 px"), value: 800 },
                            { label: Tr.t("1200 px"), value: 1200 }
                        ]
                        Choice {
                            required property var modelData
                            text: modelData.label
                            selected: (rule.modelData.height || 0) === modelData.value
                            onClicked: page.setRule(index, { height: modelData.value })
                        }
                    }
                }
            }
        }
    }
    Button {
        Layout.fillWidth: true
        text: Tr.t("Add a rule for an app")
        onClicked: page.d.windowRules = Array.from(page.d.windowRules || []).concat([{ app: "", float: false, workspace: "", width: 0 }])
    }

    // ---- workspace bar: label modes, hidden names, indicators --------------------
    SectionTitle { Layout.fillWidth: true; text: Tr.t("Workspaces in the bar") }
    Picks {
        label: Tr.t("Workspace label")
        options: [
            { label: Tr.t("Name, else number"), value: "name_or_index" },
            { label: Tr.t("Name"), value: "name" },
            { label: Tr.t("Number"), value: "index" },
            { label: Tr.t("Number and name"), value: "both" }
        ]
        current: page.d.wsLabelMode || "name_or_index"
        onPicked: v => page.d.wsLabelMode = v
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Show workspace position")
        hint: Tr.t("append the workspace's place among the visible ones")
        checked: page.d.wsShowPosition
        onToggled: on => page.d.wsShowPosition = on
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Hide empty workspaces")
        hint: Tr.t("empty workspaces are not shown in the bar; the one you are on always is")
        checked: page.d.hideEmptyWorkspaces !== false
        onToggled: on => page.d.hideEmptyWorkspaces = on
    }
    TextField {
        Layout.fillWidth: true
        placeholder: Tr.t("Hidden workspace names, comma separated")
        label: Tr.t("Hidden workspaces")
        text: (page.d.hiddenWorkspaces || []).join(", ")
        onTextChanged: {
            page.d.hiddenWorkspaces = text.split(",").map(s => s.trim()).filter(s => s !== "");
        }
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Scrollable view indicator")
        hint: Tr.t("a ribbon in the bar showing where the visible part of the workspace row is")
        checked: page.d.showRibbon
        onToggled: on => page.d.showRibbon = on
    }
    Picks {
        label: Tr.t("View indicator anchor")
        options: [{ label: Tr.t("Fit"), value: "fit" }, { label: Tr.t("Center focused column"), value: "center" }]
        current: page.d.ribbonAnchor || "fit"
        onPicked: v => page.d.ribbonAnchor = v
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Workspace window map")
        hint: Tr.t("show each tiled window as a small rectangle in the bar")
        checked: page.d.showWorkspaceMap
        onToggled: on => page.d.showWorkspaceMap = on
    }
    Picks {
        label: Tr.t("Map shows")
        options: [
            { label: Tr.t("This screen"), value: "current" },
            { label: Tr.t("All screens"), value: "all" },
            { label: Tr.t("Chosen screens"), value: "custom" }
        ]
        current: page.d.wsMapScope || "current"
        onPicked: v => page.d.wsMapScope = v
    }
    TextField {
        Layout.fillWidth: true
        visible: page.d.wsMapScope === "custom"
        placeholder: Tr.t("Screen names, comma separated (e.g. DP-1, HDMI-A-1)")
        label: Tr.t("Mapped screens")
        text: (page.d.wsMapOutputs || []).join(", ")
        onTextChanged: page.d.wsMapOutputs = text.split(",").map(s => s.trim()).filter(s => s !== "")
    }
    Picks {
        label: Tr.t("Visible part")
        options: [
            { label: Tr.t("Off"), value: "off" },
            { label: Tr.t("Highlight"), value: "highlight" },
            { label: Tr.t("Separate"), value: "separate" },
            { label: Tr.t("Both"), value: "both" }
        ]
        current: page.d.wsMapViewportMode || "highlight"
        onPicked: v => page.d.wsMapViewportMode = v
    }
    SwitchRow {
        Layout.fillWidth: true
        text: Tr.t("Show floating windows in the map")
        hint: Tr.t("Include windows that are not attached to a workspace")
        checked: page.d.wsMapFloating !== false
        onToggled: on => page.d.wsMapFloating = on
    }

    Text {
        Layout.fillWidth: true
        text: Tr.t("Windows sit side by side in columns that scroll; Mod+R cycles a column's width, Mod+F makes it full, Mod+O shows every workspace.")
        color: Theme.faint
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: Theme.px(11) * Theme.fontScale
    }
}
