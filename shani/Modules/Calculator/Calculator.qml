// The calculator (Calculator): a keypad panel over the Calculator service.
// The service owns the display string, evaluation (the safe Calc.js-style
// calc()), memory and history; this surface only draws them and sends keys.
// Tabs: Standard keypad, Scientific (trigonometry, logs, factorials, nPr/nCr,
// unary ops), and a unit Converter using the service's synced copy of
// Calc.js convert() with From/To unit pickers. Typing works too: digits and
// operators go straight to the calculator as the keys do, Escape closes,
// Enter evaluates, Ctrl+C copies.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

PanelWindow {
    id: win
    visible: Services.Calculator.shown && !Services.Lock.locked
    screen: Quickshell.screens.find(s => s.name === Services.Niri.focusedOutput) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.scrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "shani-calculator"
    // blur behind the card, as on every shell surface (ext-background-effect)
    BackgroundEffect.blurRegion: Settings.blurWanted && visible ? blurArea : null
    Region { id: blurArea; item: card; radius: card.radius }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // standard keypad: digits, + − × ÷ ( ), √, %, ±, π, e, C, copy and backspace.
    // `key` is what the service hears; `label` is what is drawn.
    readonly property var keys: [
        { label: "C", key: "C", kind: "danger" }, { label: "(", key: "(" }, { label: ")", key: ")" }, { label: "%", key: "%" }, { label: "÷", key: "/" },
        { label: "7", key: "7" }, { label: "8", key: "8" }, { label: "9", key: "9" }, { label: "×", key: "*" }, { label: "√", key: "sqrt" },
        { label: "4", key: "4" }, { label: "5", key: "5" }, { label: "6", key: "6" }, { label: "−", key: "-" }, { label: "⌫", key: "Backspace" },
        { label: "1", key: "1" }, { label: "2", key: "2" }, { label: "3", key: "3" }, { label: "+", key: "+" }, { label: "e", key: "e" },
        { label: "±", key: "neg" }, { label: "0", key: "0" }, { label: ".", key: "." }, { label: "π", key: "pi" }, { label: "=", key: "=", kind: "primary" }
    ]

    // scientific row: function inserts, then the standard keypad below
    readonly property var sciKeys: [
        { label: "sin", key: "sin" }, { label: "cos", key: "cos" }, { label: "tan", key: "tan" }, { label: "asin", key: "asin" }, { label: "acos", key: "acos" },
        { label: "atan", key: "atan" }, { label: "ln", key: "ln" }, { label: "log", key: "log" }, { label: "exp", key: "exp" }, { label: "x^y", key: "^" },
        { label: "x²", key: "sq" }, { label: "1/x", key: "recip" }, { label: "|x|", key: "|" }, { label: "x!", key: "fact" }, { label: "floor", key: "floor" },
        { label: "ceil", key: "ceil" }, { label: "nPr", key: "npr" }, { label: "nCr", key: "ncr" }, { label: "pow", key: "pow" }, { label: "abs", key: "abs" }
    ]

    // ---- converter state ---------------------------------------------------
    // the service keeps a synced copy of Calc.js's convert() table (singletons
    // can't import a library from Modules), so the unit list comes from it
    readonly property var unitList: Services.Calculator.unitNames
    property string fromUnit: "mm"
    property string toUnit: "km"
    property string converted: "—"        // last "x unit" result text, "—" when none
    property real convertedValue: 0

    property string tab: "standard"       // standard | scientific | converter

    function cycleUnit(which) {
        const cur = which === "from" ? win.fromUnit : win.toUnit;
        const i = win.unitList.indexOf(cur);
        const nxt = win.unitList[(i + 1) % win.unitList.length];
        if (which === "from")
            win.fromUnit = nxt;
        else
            win.toUnit = nxt;
        doConvert();
    }
    function doConvert() {
        const r = Services.Calculator.convertUnit(valueField.text || "", win.fromUnit, win.toUnit);
        win.converted = r ? r.text : "—";
        if (r)
            win.convertedValue = r.value;
    }

    MouseArea { anchors.fill: parent; onClicked: Services.Calculator.close() }
    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Services.Calculator.close()
        Keys.onReturnPressed: Services.Calculator.evaluate()
        Keys.onEnterPressed: Services.Calculator.evaluate()
        Keys.onBackspacePressed: Services.Calculator.backspace()
        Keys.onDeletePressed: Services.Calculator.clear()
        Keys.onPressed: e => {
            // typing goes to the calculator as the keys do (the converter's
            // value field has its own focus, so it is not disturbed)
            const t = e.text;
            if ((t >= "0" && t <= "9") || ["+", "-", "*", "/", "%", "(", ")", ".", "^", "!", "|"].indexOf(t) >= 0) {
                Services.Calculator.press(t);
                e.accepted = true;
            }
        }
    }

    Glass {
        id: card
        anchors.centerIn: parent
        width: win.tab === "converter" ? 400 : win.tab === "scientific" ? 440 : 360
        implicitHeight: Math.min(parent.height - 60, col.implicitHeight + 40)
        strong: true
        radius: Theme.radiusLarge
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Calculator")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15 * Theme.fontScale
                    font.weight: Font.DemiBold
                }
                IconButton { icon: "edit-copy"; size: 28; tip: Tr.t("Copy result"); onClicked: Services.Calculator.copyResult() }
                IconButton { icon: "window-close"; size: 28; onClicked: Services.Calculator.close() }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Choice { text: Tr.t("Standard"); selected: win.tab === "standard"; onClicked: win.tab = "standard" }
                Choice { text: Tr.t("Scientific"); selected: win.tab === "scientific"; onClicked: win.tab = "scientific" }
                Choice { text: Tr.t("Converter"); selected: win.tab === "converter"; onClicked: win.tab = "converter" }
            }

            Rectangle {
                radius: Theme.radiusSmall
                color: Theme.hover
                implicitHeight: 72
                Layout.fillWidth: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideLeft
                        text: Services.Calculator.error !== "" ? Services.Calculator.error : Services.Calculator.display
                        color: Services.Calculator.error !== "" ? Theme.danger : Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 26 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: Services.Calculator.error !== "" ? "" : Services.Calculator.preview !== "" ? "= " + Services.Calculator.preview : Services.Calculator.hasMemory ? "M = " + Services.Calculator.memory : ""
                        color: Theme.dim
                        elide: Text.ElideLeft
                        font.family: Theme.mono
                        font.pixelSize: 13 * Theme.fontScale
                    }
                }
            }

            // ---- memory (standard + scientific) -----------------------------
            RowLayout {
                visible: win.tab !== "converter"
                Layout.fillWidth: true
                spacing: 6
                Button { text: "MC"; enabled: Services.Calculator.hasMemory; onClicked: Services.Calculator.memoryClear() }
                Button { text: "MR"; enabled: Services.Calculator.hasMemory; onClicked: Services.Calculator.memoryRecall() }
                Button { text: "M+"; onClicked: Services.Calculator.memoryAdd() }
                Button { text: "M−"; onClicked: Services.Calculator.memorySubtract() }
                Text {
                    visible: Services.Calculator.hasMemory
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: "M = " + Services.Calculator.memory
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 11 * Theme.fontScale
                }
            }

            // ---- standard keypad --------------------------------------------
            GridLayout {
                visible: win.tab !== "converter"
                Layout.fillWidth: true
                columns: 5
                columnSpacing: 6
                rowSpacing: 6
                Repeater {
                    model: win.keys
                    Button {
                        required property var modelData
                        text: modelData.label
                        kind: modelData.kind || "plain"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 44
                        onClicked: {
                            if (modelData.key === "copy")
                                Services.Calculator.copyResult();
                            else
                                Services.Calculator.press(modelData.key);
                        }
                    }
                }
            }

            // ---- scientific keys ---------------------------------------------
            GridLayout {
                visible: win.tab === "scientific"
                Layout.fillWidth: true
                columns: 5
                columnSpacing: 6
                rowSpacing: 6
                Repeater {
                    model: win.sciKeys
                    Button {
                        required property var modelData
                        text: modelData.label
                        kind: "plain"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 38
                        onClicked: Services.Calculator.press(modelData.key)
                    }
                }
            }

            // ---- unit converter ----------------------------------------------
            ColumnLayout {
                visible: win.tab === "converter"
                Layout.fillWidth: true
                spacing: 10
                TextField {
                    id: valueField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Value, e.g. 100")
                    label: Tr.t("Value")
                    onAccepted: win.doConvert()
                    onTextChanged: win.doConvert()
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: Tr.t("From"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    Button { text: win.fromUnit + " ▸"; Layout.fillWidth: true; onClicked: win.cycleUnit("from") }
                    Button { text: "⇄"; onClicked: { const t = win.fromUnit; win.fromUnit = win.toUnit; win.toUnit = t; win.doConvert(); } }
                    Text { text: Tr.t("To"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    Button { text: win.toUnit + " ▸"; Layout.fillWidth: true; onClicked: win.cycleUnit("to") }
                }
                Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    implicitHeight: 56
                    Layout.fillWidth: true
                    Text {
                        anchors.centerIn: parent
                        text: win.converted
                        color: win.converted === "—" ? Theme.dim : Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 17 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                }
                Button {
                    Layout.fillWidth: true
                    visible: win.converted !== "—"
                    text: Tr.t("Use result in calculator")
                    onClicked: { Services.Calculator.clear(); Services.Calculator.display = String(win.convertedValue); win.tab = "standard"; }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("Length, mass, volume, data, time, speed, area and °C/°F/K")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
            }

            // ---- history: last 20 evaluations, click to recall ---------------
            ColumnLayout {
                visible: win.tab !== "converter" && Services.Calculator.history.length > 0
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t("History")
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                    Button { text: Tr.t("Clear"); kind: "plain"; onClicked: Services.Calculator.clearHistory() }
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(120, histCol.implicitHeight + 4)
                    Layout.minimumHeight: 24
                    contentHeight: histCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: histCol
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: Services.Calculator.history
                            Button {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                text: modelData.expr + " = " + modelData.value
                                kind: "plain"
                                onClicked: Services.Calculator.recallHistory(index)
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: win.tab === "converter" ? Tr.t("Tap a unit to cycle · Enter converts") : Tr.t("Type to calculate · Esc closes · Enter = · Ctrl+C copies")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11 * Theme.fontScale
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: Services.Calculator.close() }
    Shortcut { sequence: "Return"; onActivated: Services.Calculator.evaluate() }
    Shortcut { sequence: "Enter"; onActivated: Services.Calculator.evaluate() }
    Shortcut { sequence: "Ctrl+C"; onActivated: Services.Calculator.copyResult() }
}
