// The calculator (Calculator): a keypad panel over the Calculator service.
// The service owns the display string, evaluation (the safe Calc.js-style
// calc()), memory and history; this surface only draws them and sends keys.
// Tabs: Standard keypad, Scientific (trigonometry, logs, factorials, nPr/nCr,
// unary ops), a unit Converter using the service's synced copy of
// Calc.js convert() with From/To unit pickers, Financial (periodic interest
// rate, future/present value, straight-line + double-declining depreciation)
// and Programming (bin/oct/dec/hex base switching, bitwise AND/OR/XOR/NOT/
// shifts, two's complement at 8/16/32/64 bits, char <-> code conversion).
// Typing works too: digits and operators go straight to the calculator as
// the keys do (A-F in Programming), Escape closes, Enter evaluates,
// Ctrl+C copies.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services as Services

AppWindow {
    id: win
    appName: "Calculator"
    tools: [
        IconButton { size: 30; icon: "edit-copy"; tip: Tr.t("Copy result"); onClicked: Services.Calculator.copyResult() }
    ]
    visible: Services.Calculator.shown
    onGone: Services.Calculator.close()
    margins: 0
    implicitWidth: 460
    implicitHeight: Math.max(320, Math.min(900, col.implicitHeight + 40))
    // blur behind the card, as on every shell surface (ext-background-effect)

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

    // financial row: every entry inserts a whitelist function name
    // (fv/pv/rate/sl/ddb); the Financial tab computes with the four
    // argument fields below through Services.Calculator.financial().
    readonly property var finKeys: [
        { label: "fv", key: "fv" }, { label: "pv", key: "pv" }, { label: "rate", key: "rate" }, { label: "sl", key: "sl" }, { label: "ddb", key: "ddb" }
    ]

    // programming row: bitwise ops (band/bor/bxor/bnot/lsh/rsh) + base keys
    readonly property var progKeys: [
        { label: "AND", key: "band" }, { label: "OR", key: "bor" }, { label: "XOR", key: "bxor" }, { label: "NOT", key: "bnot" }, { label: "A", key: "A" },
        { label: "B", key: "B" }, { label: "C", key: "C" }, { label: "D", key: "D" }, { label: "E", key: "E" }, { label: "F", key: "F" },
        { label: "«", key: "lsh" }, { label: "»", key: "rsh" }, { label: "0", key: "0" }, { label: "(", key: "(" }, { label: ")", key: ")" }
    ]

    // ---- converter state ---------------------------------------------------
    // the service keeps a synced copy of Calc.js's convert() table (singletons
    // can't import a library from Modules), so the unit list comes from it
    readonly property var unitList: Services.Calculator.unitNames
    property string fromUnit: "mm"
    property string toUnit: "km"
    property string converted: "—"        // last "x unit" result text, "—" when none
    property real convertedValue: 0

    property string tab: "standard"       // standard | scientific | converter | financial | programming
    onTabChanged: Ui.calculatorTab = win.tab

    // ---- financial state (tab: financial) ---------------------------------
    // four argument fields reused by every op; the op button decides which
    // of them the op consumes (fv/pv/rate/sl take 3, ddb takes 4).
    property string finOp: "fv"
    function doFinancial() {
        Services.Calculator.financial(win.finOp, faField.text || "", fbField.text || "", fcField.text || "", fdField.text || "");
    }

    // ---- programming state (tab: programming) ------------------------------
    property string progOp: "and"
    function doProgramming() {
        // one "value" field drives baseOutputs(); the bitwise row below
        // uses paField/pbField directly via Services.Calculator.programming()
        const v = progValueField.text || "";
        Services.Calculator.baseOutputs(v);
        Services.Calculator.twosComplementString(v, Services.Calculator.width);
    }
    function cycleBase() {
        const order = ["bin", "oct", "dec", "hex"];
        const i = order.indexOf(Services.Calculator.base);
        Services.Calculator.setBase(order[(i + 1) % order.length]);
        doProgramming();
    }
    function cycleWidth() {
        const order = [8, 16, 32, 64];
        const i = order.indexOf(Services.Calculator.width);
        Services.Calculator.setWidth(order[(i + 1) % order.length]);
        doProgramming();
    }

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

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: Services.Calculator.close()
        Keys.onReturnPressed: Services.Calculator.evaluate()
        Keys.onEnterPressed: Services.Calculator.evaluate()
        Keys.onDeletePressed: Services.Calculator.clear()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Backspace) {
                Services.Calculator.backspace();
                e.accepted = true;
                return;
            }
            // typing goes to the calculator as the keys do (the converter's
            // and the financial/programming value fields have their own
            // focus, so they are not disturbed). In Programming, A-F are
            // hex digits and go to the calculator too.
            const t = e.text;
            if ((t >= "0" && t <= "9") || ["+", "-", "*", "/", "%", "(", ")", ".", "^", "!", "|"].indexOf(t) >= 0
                || (win.tab === "programming" && /^[A-Fa-f]$/.test(t))) {
                Services.Calculator.press(t);
                e.accepted = true;
            }
        }
    }

    Item {
        id: card
        anchors.fill: parent
        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10


            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Choice { text: Tr.t("Standard"); selected: win.tab === "standard"; onClicked: win.tab = "standard" }
                Choice { text: Tr.t("Scientific"); selected: win.tab === "scientific"; onClicked: win.tab = "scientific" }
                Choice { text: Tr.t("Financial"); selected: win.tab === "financial"; onClicked: win.tab = "financial" }
                Choice { text: Tr.t("Programming"); selected: win.tab === "programming"; onClicked: win.tab = "programming" }
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
                visible: win.tab === "standard" || win.tab === "scientific"
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
                visible: win.tab === "standard" || win.tab === "scientific"
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

            // ---- financial (GNOME Calculator parity) -------------------------
            // fv = future value P*(1+r)^n · pv = present value FV/(1+r)^n ·
            // rate = periodic interest rate solving pmt = P*r/(1-(1+r)^-n) ·
            // sl = straight-line (cost-salvage)/life ·
            // ddb = double-declining-balance in the given period. Every op
            // goes through Services.Calculator.financial() → calc() whitelist.
            ColumnLayout {
                visible: win.tab === "financial"
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Choice { text: Tr.t("Future value"); selected: win.finOp === "fv"; onClicked: { win.finOp = "fv"; win.doFinancial(); } }
                    Choice { text: Tr.t("Present value"); selected: win.finOp === "pv"; onClicked: { win.finOp = "pv"; win.doFinancial(); } }
                    Choice { text: Tr.t("Rate"); selected: win.finOp === "rate"; onClicked: { win.finOp = "rate"; win.doFinancial(); } }
                    Choice { text: Tr.t("SL"); selected: win.finOp === "sl"; onClicked: { win.finOp = "sl"; win.doFinancial(); } }
                    Choice { text: Tr.t("DDB"); selected: win.finOp === "ddb"; onClicked: { win.finOp = "ddb"; win.doFinancial(); } }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    TextField { id: faField; Layout.fillWidth: true; placeholder: Tr.t("Principal / cost"); label: Tr.t("A (principal / cost)"); onAccepted: win.doFinancial(); onTextChanged: win.doFinancial() }
                    TextField { id: fbField; Layout.fillWidth: true; placeholder: Tr.t("Rate / payment / salvage"); label: Tr.t("B"); onAccepted: win.doFinancial(); onTextChanged: win.doFinancial() }
                    TextField { id: fcField; Layout.fillWidth: true; placeholder: Tr.t("Periods / life"); label: Tr.t("C"); onAccepted: win.doFinancial(); onTextChanged: win.doFinancial() }
                    TextField { id: fdField; Layout.fillWidth: true; visible: win.finOp === "ddb"; placeholder: Tr.t("Period (DDB only)"); label: Tr.t("D"); onAccepted: win.doFinancial(); onTextChanged: win.doFinancial() }
                }
                Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    implicitHeight: 56
                    Layout.fillWidth: true
                    Text {
                        anchors.centerIn: parent
                        text: Services.Calculator.finResult
                        color: Services.Calculator.finResult === "—" ? Theme.dim : Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 17 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: win.finKeys
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
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: win.finOp === "fv" ? Tr.t("fv(principal, rate, periods) — future value")
                        : win.finOp === "pv" ? Tr.t("pv(future value, rate, periods) — present value")
                        : win.finOp === "rate" ? Tr.t("rate(principal, periodic payment, periods)")
                        : win.finOp === "sl" ? Tr.t("sl(cost, salvage, life) — straight-line depreciation")
                        : Tr.t("ddb(cost, salvage, life, period) — double-declining balance")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                    wrapMode: Text.WordWrap
                }
            }

            // ---- programming (GNOME Calculator parity) -----------------------
            // bin/oct/dec/hex output, bitwise AND/OR/XOR/NOT/shifts,
            // two's complement at 8/16/32/64 bits, char <-> code conversion.
            ColumnLayout {
                visible: win.tab === "programming"
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: progValueField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Value, e.g. 255")
                    label: Tr.t("Value (decimal)")
                    onAccepted: win.doProgramming()
                    onTextChanged: win.doProgramming()
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: Tr.t("Base"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    Button { text: Services.Calculator.base + " ▸"; Layout.fillWidth: true; onClicked: win.cycleBase() }
                    Text { text: Tr.t("Width"); color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 * Theme.fontScale }
                    Button { text: Services.Calculator.width + " ▸"; Layout.fillWidth: true; onClicked: win.cycleWidth() }
                }
                Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.hover
                    implicitHeight: 64
                    Layout.fillWidth: true
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignCenter
                            text: Services.Calculator.progBin === "" ? "—" : ("bin " + Services.Calculator.progBin + " · oct " + Services.Calculator.progOct + " · dec " + Services.Calculator.progDec + " · hex " + Services.Calculator.progHex)
                            color: Services.Calculator.progBin === "" ? Theme.dim : Theme.text
                            font.family: Theme.mono
                            font.pixelSize: 11 * Theme.fontScale
                            elide: Text.ElideLeft
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignCenter
                            text: Tr.t("two's complement") + " (" + Services.Calculator.width + "): " + Services.Calculator.twosResult
                            color: Theme.dim
                            font.family: Theme.mono
                            font.pixelSize: 11 * Theme.fontScale
                            elide: Text.ElideLeft
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField { id: paField; Layout.fillWidth: true; placeholder: Tr.t("A"); label: Tr.t("A") }
                    Button { text: "AND"; kind: "plain"; onClicked: Services.Calculator.programming("and", paField.text, pbField.text) }
                    Button { text: "OR"; kind: "plain"; onClicked: Services.Calculator.programming("or", paField.text, pbField.text) }
                    Button { text: "XOR"; kind: "plain"; onClicked: Services.Calculator.programming("xor", paField.text, pbField.text) }
                    Button { text: "NOT"; kind: "plain"; onClicked: Services.Calculator.programming("not", paField.text, "") }
                    TextField { id: pbField; Layout.fillWidth: true; placeholder: Tr.t("B / shift"); label: Tr.t("B") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Button { text: Tr.t("Left shift"); kind: "plain"; Layout.fillWidth: true; onClicked: Services.Calculator.programming("shl", paField.text, pbField.text) }
                    Button { text: Tr.t("Right shift"); kind: "plain"; Layout.fillWidth: true; onClicked: Services.Calculator.programming("shr", paField.text, pbField.text) }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: Services.Calculator.progResult
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 14 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField { id: charField; Layout.fillWidth: true; placeholder: Tr.t("Char, e.g. A"); label: Tr.t("Char"); onAccepted: Services.Calculator.charConvert(text) }
                    Button { text: Tr.t("→ code"); kind: "plain"; onClicked: Services.Calculator.charConvert(charField.text) }
                    TextField { id: codeField; Layout.fillWidth: true; placeholder: Tr.t("Code, e.g. 65"); label: Tr.t("Code"); onAccepted: { Services.Calculator.programming("fromchar", text, ""); } }
                    Button { text: Tr.t("→ char"); kind: "plain"; onClicked: Services.Calculator.programming("fromchar", codeField.text, "") }
                    Text {
                        horizontalAlignment: Text.AlignRight
                        text: Services.Calculator.charResult
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 14 * Theme.fontScale
                        font.weight: Font.DemiBold
                    }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: win.progKeys
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
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.t("64-bit two's complement is a double approximation")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * Theme.fontScale
                }
            }

            // ---- history: last 20 evaluations, click to recall ---------------
            ColumnLayout {
                visible: (win.tab === "standard" || win.tab === "scientific") && Services.Calculator.history.length > 0
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
                text: win.tab === "converter" ? Tr.t("Tap a unit to cycle · Enter converts")
                    : win.tab === "financial" ? Tr.t("Tap an op, then type A–D · Enter computes")
                    : win.tab === "programming" ? Tr.t("Type a value · base/width cycle · A–F type hex digits")
                    : Tr.t("Type to calculate · Esc closes · Enter = · Ctrl+C copies")
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
