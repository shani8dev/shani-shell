pragma Singleton
// The calculator surface (Modules/Calculator): a display string we type into
// with the keypad and evaluate in JS. Evaluation is the same safe approach
// as Modules/Launcher/Calc.js calc(): strip whitespace, normalise × ÷ ^,
// whitelist digits/operators and known function names, then evaluate the
// result through Function() with a strict wrapper. Only a finite number is
// a result; anything else (a bare number, an unknown name, a syntax error)
// is not a value.
import Quickshell
import QtQuick

Singleton {
    id: root
    property string display: "0"      // the expression being typed, or the last result
    readonly property string result: display      // what was last computed (or what is shown)
    property string preview: ""        // live "= …" while typing, "" when none
    property string error: ""          // last evaluation error, "" when the last one was fine
    property bool shown: false         // the panel is open (Modules/Calculator/Calculator.qml)
    property bool justEvaluated: false // after "=", a digit starts fresh instead of appending

    function open() { shown = true; }
    function close() { shown = false; }
    function toggle() { shown = !shown; }

    // the launcher's evaluator, copied (Modules/Launcher/Calc.js).
    function calc(expr) {
        const src = expr.replace(/\s+/g, "").replace(/\^/g, "**").replace(/×/g, "*").replace(/÷/g, "/");
        if (!/^[0-9+\-*/%.()a-z,]+$/i.test(src) || !/[0-9]/.test(src) || /^[0-9.]+$/.test(src))
            return null;
        const names = src.match(/[a-z]+/gi) || [];
        const allowed = ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "exp", "abs", "round", "floor", "ceil", "pow", "min", "max", "pi", "e"];
        if (names.some(n => allowed.indexOf(n.toLowerCase()) < 0))
            return null;
        const js = src.replace(/\bln\(/gi, "log(").replace(/\bpi\b/gi, "PI").replace(/\be\b/g, "E")
            .replace(/\b(sqrt|sin|cos|tan|asin|acos|atan|log|exp|abs|round|floor|ceil|pow|min|max|PI|E)\b/g, "Math.$1");
        try {
            const v = Function('"use strict"; return (' + js + ");")();
            return typeof v === "number" && isFinite(v) ? Number(v.toPrecision(12)) : null;
        } catch (e) {
            return null;
        }
    }

    function _refreshPreview() {
        if (display === "" || display === "0" || justEvaluated || error !== "")
            preview = "";
        else {
            const v = calc(display);
            preview = v === null ? "" : String(v);
        }
    }

    onDisplayChanged: _refreshPreview()

    function press(key) {
        const k = String(key || "");
        if (k === "" || k === "clear" || k === "C")
            return clear();
        if (k === "copy")
            return copyResult();
        if (k === "=" || k === "equals" || k === "Enter" || k === "Return")
            return evaluate();
        if (k === "Backspace" || k === "⌫" || k === "backspace" || k === "DEL" || k === "Delete")
            return backspace();
        if (k === "sqrt" || k === "√" || k === "sqrt(")
            return _appendSqrt();
        let t = k;
        if (t === "÷") t = "/";
        else if (t === "×") t = "*";
        else if (t === "−" || t === "–") t = "-";
        else if (t === "π") t = "pi";
        if (!/^[0-9+\-*/%.(),]$/.test(t) && t !== "pi")
            return;
        // after "=" or an error, typing starts again (except an operator, which continues the result)
        if (justEvaluated || error !== "") {
            if (/[0-9(]/.test(t) || t === "pi")
                clear();
            justEvaluated = false;
            error = "";
        }
        if (t === "." && _currentNumber().indexOf(".") >= 0)
            return;
        if (display === "0" && t !== "." && t !== ")")
            display = t;
        else
            display += t;
        _refreshPreview();
    }

    function _currentNumber() {
        const m = display.match(/[0-9.]*$/);
        return m ? m[0] : "";
    }

    function _appendSqrt() {
        if (justEvaluated || error !== "") {
            clear();
        }
        if (display === "0")
            display = "sqrt(";
        else
            display += "sqrt(";
        justEvaluated = false;
        error = "";
        _refreshPreview();
    }

    function insert(text) { press(text); }
    function input(text) { press(text); }

    function backspace() {
        if (display.length <= 1 || display === "0") {
            display = "0";
        } else {
            display = display.slice(0, -1) || "0";
        }
        justEvaluated = false;
        error = "";
        _refreshPreview();
    }

    function clear() {
        display = "0";
        error = "";
        preview = "";
        justEvaluated = false;
    }

    function evaluate() {
        if (display === "" || display === "0")
            return;
        // a bare number is its own value (Calc.calc refuses it, on purpose)
        if (/^-?[0-9.]+$/.test(display.replace(/\s+/g, ""))) {
            const v = Number(display);
            if (isFinite(v)) {
                display = String(Number(v.toPrecision(12)));
                error = "";
                preview = "";
                justEvaluated = true;
            }
            return;
        }
        const v = calc(display);
        if (v === null) {
            error = "Error";
            preview = "";
            justEvaluated = false;
            return;
        }
        display = String(v);
        error = "";
        preview = "";
        justEvaluated = true;
    }

    // the same name the launcher's helper has, so a caller can use either
    function equals() { evaluate(); }

    function copyResult() {
        if (display === "" || display === "0" || error !== "")
            return;
        Quickshell.clipboardText = display;
        Quickshell.execDetached(["notify-send", "-a", "Calculator", "Copied " + display]);
    }
}
