pragma Singleton
// The calculator surface (Modules/Calculator): a display string we type into
// with the keypad and evaluate in JS. The evaluator is the shell's one,
// Common/Calc.js (shared with the launcher): strip whitespace,
// normalise × ÷ ^ √ π −, rewrite |x| → abs(x) and n! → fact(n), allow only
// known function names, evaluate through Function() with a strict wrapper.
// Only a finite number is a result; anything else is not a value.
//
// Full GNOME-Calculator-style parity: scientific functions (sin/cos/tan and
// inverses, ln/log, exp, x^y, floor/ceil, abs, |x|, factorial, nPr/nCr),
// memory (MC/MR/M+/M-), history (last 20 evaluations, click to recall),
// percentage, ± toggle, 1/x, x², √x, π, e. Unit conversion (convertUnit)
// is Common/Calc.js's table (mm→km, °C/°F/K, data, speed, area,
// time) for the panel's Converter tab and the `calculatorConvert` IPC call.
// Financial (GNOME Calculator parity): fv/pv (future/present value),
// rate (periodic interest rate), sl (straight-line depreciation) and
// ddb (double-declining-basis depreciation) — all through the same
// whitelist in calc(), so an expression like fv(1000,0.05,3) evaluates
// exactly like sin(0) does. Programming: band/bor/bxor/bnot/lsh/rsh
// (bitwise AND/OR/XOR/NOT/shifts) through the same whitelist, base
// switching (bin/oct/dec/hex), two's complement at 8/16/32/64 bits and
// char <-> code conversion (charCode/codeToChar).
import Quickshell
import QtQuick
import "../Common/Calc.js" as Calc

Singleton {
    id: root
    property string display: "0"      // the expression being typed, or the last result
    readonly property string result: display      // what was last computed (or what is shown)
    property string preview: ""        // live "= …" while typing, "" when none
    property string error: ""          // last evaluation error, "" when the last one was fine
    property bool shown: false         // the panel is open (Modules/Calculator/Calculator.qml)
    property bool justEvaluated: false // after "=", a digit starts fresh instead of appending

    // Angle unit for trig (DEG default, also RAD/GRAD). The panel toggle that
    // drives setAngleUnit() lives with the shell app files; until it lands, a
    // caller can bind a DEG/RAD/GRAD selector to this property directly.
    property string angleUnit: "deg"   // deg | rad | grad

    property real memory: 0             // the memory register (MC/MR/M+/M-)
    property bool hasMemory: false
    property var history: []            // [{expr, value}] newest first, capped at 20

    // programming mode state (GNOME Calculator parity)
    property string base: "dec"      // bin | oct | dec | hex (the selected output base)
    property int width: 32           // two's complement width: 8 | 16 | 32 | 64
    property string finResult: "—"   // last financial result text for the panel and `state`
    property string progResult: "—"  // last programming result text (decimal by default)
    property string progBin: ""      // baseOutputs(): the value in binary / octal / decimal / hex
    property string progOct: ""
    property string progDec: ""
    property string progHex: ""
    property string twosResult: "—"  // two's complement display for `width`
    property string charResult: "—"  // char <-> code conversion result

    function open() { shown = true; }
    function close() { shown = false; }
    function toggle() { shown = !shown; }
    function setAngleUnit(u) {
        const s = String(u || "").toLowerCase();
        if (["deg", "rad", "grad"].indexOf(s) >= 0)
            angleUnit = s;
    }

    // the evaluator. Helpers fact/npr/ncr and the financial/programming
    // helpers below are computed with the local functions and passed into
    // the strict Function() wrapper; only a finite result survives (the
    // same rule as the launcher's calc()).
    // the shell's one evaluator (Common/Calc.js), in this calculator's angle unit
    function calc(expr) { return Calc.calc(expr, root.angleUnit); }

    // ---- financial ----------------------------------------------------------
    // Each op builds the same expression calc() would evaluate, so the
    // panel and the `calculatorFinancial` IPC call go through the exact
    // same whitelist (no new evaluator). `rate` is bisection-solved
    // inside calc()'s helper above, so its result is a periodic rate
    // (per-period, not annualised).
    function financial(op, a, b, c, d) {
        const o = String(op || "").toLowerCase();
        const p = function (x) { return parseFloat(String(x === undefined || x === null ? "" : x).replace(/\s+/g, "")); };
        let expr = "";
        if (o === "fv" || o === "futurevalue" || o === "future")
            expr = "fv(" + p(a) + "," + p(b) + "," + p(c) + ")";
        else if (o === "pv" || o === "presentvalue" || o === "present")
            expr = "pv(" + p(a) + "," + p(b) + "," + p(c) + ")";
        else if (o === "rate" || o === "periodic" || o === "periodicinterestrate" || o === "periodicinterest")
            expr = "rate(" + p(a) + "," + p(b) + "," + p(c) + ")";
        else if (o === "sl" || o === "straightline" || o === "straight" || o === "straightlinedepreciation")
            expr = "sl(" + p(a) + "," + p(b) + "," + p(c) + ")";
        else if (o === "ddb" || o === "doubledeclining" || o === "doubledecliningbalance" || o === "doubledecliningdepreciation")
            expr = "ddb(" + p(a) + "," + p(b) + "," + p(c) + "," + p(d) + ")";
        else
            return null;
        const v = calc(expr);
        finResult = v === null ? "—" : String(Number(v.toPrecision(12)));
        return v;
    }
    function finFutureValue(principal, rate, periods) { return financial("fv", principal, rate, periods, ""); }
    function finPresentValue(futureValue, rate, periods) { return financial("pv", futureValue, rate, periods, ""); }
    function finPeriodicRate(principal, payment, periods) { return financial("rate", principal, payment, periods, ""); }
    function finStraightLine(cost, salvage, life) { return financial("sl", cost, salvage, life, ""); }
    function finDoubleDeclining(cost, salvage, life, period) { return financial("ddb", cost, salvage, life, period); }

    // ---- programming: bases, two's complement, char codes -------------------
    function setBase(b) {
        const s = String(b || "").toLowerCase();
        if (["bin", "oct", "dec", "hex"].indexOf(s) >= 0)
            base = s;
    }
    function setWidth(w) {
        const n = Number(w);
        if ([8, 16, 32, 64].indexOf(n) >= 0)
            width = n;
    }
    // the value in base b (bin/oct/dec/hex); negatives render as 32-bit
    // unsigned for bin/oct/hex, signed for dec — the panel shows all four
    function toBase(value, b) {
        const v = parseFloat(value);
        if (!isFinite(v))
            return "";
        const n = Math.floor(v);
        const bb = String(b || "").toLowerCase();
        if (bb === "bin" || bb === "2")
            return (n >>> 0).toString(2);
        if (bb === "oct" || bb === "8")
            return (n >>> 0).toString(8);
        if (bb === "hex" || bb === "16" || bb === "x")
            return (n >>> 0).toString(16).toUpperCase();
        return String(n); // dec
    }
    function fromBase(text, b) {
        const s = String(text || "").trim();
        if (s === "")
            return null;
        const bb = String(b || "").toLowerCase();
        let radix = 10;
        if (bb === "bin" || bb === "2")
            radix = 2;
        else if (bb === "oct" || bb === "8")
            radix = 8;
        else if (bb === "hex" || bb === "16" || bb === "x")
            radix = 16;
        const t = s.replace(/^(0[xX]|0[bB]|0[oO])/, "");
        if (t === "" || !new RegExp("^(-)?[0-9a-z]+$", "i").test(t))
            return null;
        const v = parseInt(t, radix);
        return isFinite(v) && !isNaN(v) ? v : null;
    }
    function baseOutputs(value) {
        const v = parseFloat(value);
        if (!isFinite(v))
            return null;
        const n = Math.floor(v);
        const out = { bin: toBase(n, "bin"), oct: toBase(n, "oct"), dec: toBase(n, "dec"), hex: toBase(n, "hex") };
        progBin = out.bin; progOct = out.oct; progDec = out.dec; progHex = out.hex;
        progResult = out.dec;
        return out;
    }
    // two's complement: the unsigned value of `value` in `bits` (e.g. -1
    // in 8 bits is 255). Works for 8/16/32; 64 is a double approximation
    // beyond Number.MAX_SAFE_INTEGER, documented on the panel.
    function twosComplement(value, bits) {
        const w = [8, 16, 32, 64].indexOf(Number(bits)) >= 0 ? Number(bits) : 32;
        const v = parseFloat(value);
        if (!isFinite(v))
            return null;
        const n = Math.floor(v);
        if (w === 64) {
            const m = Math.pow(2, 64);
            return ((n % m) + m) % m;
        }
        const m = Math.pow(2, w);
        return ((n % m) + m) % m;
    }
    function twosComplementString(value, bits) {
        const w = [8, 16, 32, 64].indexOf(Number(bits)) >= 0 ? Number(bits) : 32;
        const u = twosComplement(value, w);
        if (u === null)
            return "";
        let s = u.toString(2);
        while (s.length < w)
            s = "0" + s;
        twosResult = s + " (" + String(u) + ")";
        return s;
    }
    // generic programming op for the panel and `calculatorProgramming`.
    // Bitwise ops go through calc()'s whitelist (band/bor/...); bases,
    // two's complement and char codes are direct (they need strings).
    function programming(op, a, b) {
        const o = String(op || "").toLowerCase();
        const p = function (x) { return parseFloat(String(x === undefined || x === null ? "" : x).replace(/\s+/g, "")); };
        if (o === "and" || o === "band")
            return _progCalc("band(" + p(a) + "," + p(b) + ")");
        if (o === "or" || o === "bor")
            return _progCalc("bor(" + p(a) + "," + p(b) + ")");
        if (o === "xor" || o === "bxor")
            return _progCalc("bxor(" + p(a) + "," + p(b) + ")");
        if (o === "not" || o === "bnot")
            return _progCalc("bnot(" + p(a) + ")");
        if (o === "shl" || o === "lsh" || o === "shiftleft" || o === "shift-left")
            return _progCalc("lsh(" + p(a) + "," + p(b) + ")");
        if (o === "shr" || o === "rsh" || o === "shiftright" || o === "shift-right")
            return _progCalc("rsh(" + p(a) + "," + p(b) + ")");
        if (o === "tobase") {
            const s = toBase(a, b || base);
            progResult = s === "" ? "—" : s;
            return s === "" ? null : fromBase(s, b || base);
        }
        if (o === "frombase") {
            const v = fromBase(a, b || base);
            progResult = v === null ? "—" : String(v);
            baseOutputs(v === null ? "" : v);
            return v;
        }
        if (o === "twos" || o === "twoscomplement" || o === "twos-complement") {
            const w = [8, 16, 32, 64].indexOf(Number(b)) >= 0 ? Number(b) : width;
            const s = twosComplementString(a, w);
            if (s !== "")
                progResult = twosResult;
            return twosComplement(a, w);
        }
        if (o === "charcode" || o === "char" || o === "charcodeof") {
            const v = charCode(a);
            charResult = v === null ? "—" : String(v);
            progResult = charResult;
            return v;
        }
        if (o === "fromchar" || o === "charfromcode" || o === "codechar") {
            const s = codeToChar(a);
            charResult = s === "" ? "—" : s;
            progResult = charResult;
            return s === "" ? null : charCode(s);
        }
        if (o === "bases" || o === "outputs") {
            const out = baseOutputs(a);
            return out ? parseFloat(out.dec) : null;
        }
        return null;
    }
    function _progCalc(expr) {
        const v = calc(expr);
        progResult = v === null ? "—" : String(v);
        return v;
    }
    function progBand(a, b) { return programming("and", a, b); }
    function progOr(a, b) { return programming("or", a, b); }
    function progXor(a, b) { return programming("xor", a, b); }
    function progNot(a) { return programming("not", a, ""); }
    function progShl(a, n) { return programming("shl", a, n); }
    function progShr(a, n) { return programming("shr", a, n); }
    // character <-> character-code conversion (GNOME Programming parity)
    function charCode(text) {
        const s = String(text === undefined || text === null ? "" : text);
        return s.length ? s.charCodeAt(0) : null;
    }
    function codeToChar(code) {
        const n = Math.floor(Number(code));
        if (!isFinite(n) || n < 0 || n > 0x10FFFF)
            return "";
        try {
            return String.fromCodePoint(n);
        } catch (e) {
            return n < 65536 ? String.fromCharCode(n) : "";
        }
    }
    function charConvert(text) {
        const v = charCode(text);
        charResult = v === null ? "—" : String(v);
        progResult = charResult;
        return v;
    }

    // unit conversion: Common/Calc.js's table, shared with the launcher
    readonly property var units: Calc.units
    readonly property var unitNames: Object.keys(units).sort()

    function convertUnit(value, from, to) { return Calc.convertUnit(value, from, to); }

    function _refreshPreview() {
        if (display === "" || display === "0" || justEvaluated || error !== "")
            preview = "";
        else {
            const v = calc(display);
            preview = v === null ? "" : String(v);
        }
    }

    onDisplayChanged: _refreshPreview()

    // the number the unary operations act on (bare display or last preview)
    function _value() {
        const plain = display.replace(/\s+/g, "");
        if (/^-?[0-9.]+$/.test(plain)) {
            const v = Number(plain);
            return isFinite(v) ? v : null;
        }
        const v = calc(display);
        return v === null ? null : v;
    }

    function _apply(fn) {
        const v = _value();
        if (v === null || !isFinite(v))
            return;
        const out = fn(v);
        if (!isFinite(out))
            return;
        display = String(Number(out.toPrecision(12)));
        justEvaluated = true;
        error = "";
        _refreshPreview();
    }

    function toggleSign() {
        // plain numbers negate directly; expressions negate as a whole
        const plain = display.replace(/\s+/g, "");
        if (/^-?[0-9.]+$/.test(plain)) {
            _apply(x => -x);
            return;
        }
        if (display.charAt(0) === "-")
            display = display.slice(1);
        else
            display = "-(" + display + ")";
        justEvaluated = false;
        error = "";
        _refreshPreview();
    }
    function percent() { _apply(x => x / 100); }
    function reciprocal() { _apply(x => x === 0 ? NaN : 1 / x); }   // NaN → _apply guard treats as no-op
    function square() { _apply(x => x * x); }
    function sqrtVal() {
        const v = _value();
        if (v === null || v < 0 || !isFinite(v))
            return;
        display = String(Number(Math.sqrt(v).toPrecision(12)));
        justEvaluated = true;
        error = "";
        _refreshPreview();
    }

    function memoryClear() { memory = 0; hasMemory = false; }
    function memoryRecall() {
        if (!hasMemory)
            return;
        display = String(Number(memory.toPrecision(12)));
        justEvaluated = true;
        error = "";
        _refreshPreview();
    }
    function _memOp(sign) {
        const v = _value();
        if (v === null)
            return;
        memory = hasMemory ? memory + sign * v : v;
        hasMemory = true;
    }
    function memoryAdd() { _memOp(1); }
    function memorySubtract() { _memOp(-1); }

    function clearHistory() { history = []; }
    function recallHistory(idx) {
        const h = history[idx];
        if (!h)
            return;
        display = h.value;
        justEvaluated = true;
        error = "";
        _refreshPreview();
    }

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
        if (k === "neg")
            return toggleSign();
        if (k === "%")
            return percent();
        if (k === "recip")
            return reciprocal();
        if (k === "sq")
            return square();
        if (k === "sqrt" || k === "√" || k === "sqrt(")
            return _appendFn("sqrt");
        if (["sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "exp", "abs", "floor", "ceil", "npr", "ncr", "fact", "pow", "fv", "pv", "rate", "sl", "ddb", "band", "bor", "bxor", "bnot", "lsh", "rsh"].indexOf(k.toLowerCase()) >= 0)
            return _appendFn(k.toLowerCase());
        if (k === "^" || k === "x^y")
            return _appendChar("^");
        if (k === "|")
            return _appendChar("|");
        if (k === "!")
            return _appendChar("!");
        if (k === "π")
            return _appendChar("pi");
        if (k === "e")
            return _appendChar("e");
        // a bare hex digit (programming mode): A-F type onto the display
        if (/^[A-Fa-f]$/.test(k))
            return _appendChar(k.toUpperCase());
        // digits and basic operators
        let t = k;
        if (t === "÷") t = "/";
        else if (t === "×") t = "*";
        else if (t === "−" || t === "–") t = "-";
        if (!/^[0-9+\-*/%.(),]$/.test(t) && t !== "pi" && t !== "e")
            return;
        _appendChar(t);
    }

    function _appendChar(t) {
        // after "=" or an error, typing starts again (except an operator, which continues the result)
        if (justEvaluated || error !== "") {
            if (/[0-9(]/.test(t) || t === "pi" || t === "e")
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

    function _appendFn(name) {
        if (justEvaluated || error !== "")
            clear();
        if (display === "0")
            display = name + "(";
        else
            display += name + "(";
        justEvaluated = false;
        error = "";
        _refreshPreview();
    }

    function _currentNumber() {
        const m = display.match(/[0-9.]*$/);
        return m ? m[0] : "";
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
        // a bare number is its own value (calc() refuses it, on purpose)
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
        const before = display;
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
        // history: newest first, last 20 only
        const next = [{ expr: before, value: String(v) }].concat(history).slice(0, 20);
        history = next;
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
