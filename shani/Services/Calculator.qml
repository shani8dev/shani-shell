pragma Singleton
// The calculator surface (Modules/Calculator): a display string we type into
// with the keypad and evaluate in JS. Safe evaluator (same whitelist +
// Function() approach as Modules/Launcher/Calc.js calc()): strip whitespace,
// normalise × ÷ ^ √ π −, rewrite |x| → abs(x) and n! → fact(n), allow only
// known function names, evaluate through Function() with a strict wrapper.
// Only a finite number is a result; anything else is not a value.
//
// Full GNOME-Calculator-style parity: scientific functions (sin/cos/tan and
// inverses, ln/log, exp, x^y, floor/ceil, abs, |x|, factorial, nPr/nCr),
// memory (MC/MR/M+/M-), history (last 20 evaluations, click to recall),
// percentage, ± toggle, 1/x, x², √x, π, e. Unit conversion (convertUnit)
// mirrors the Calc.js convert() table (mm→km, °C/°F/K, data, speed, area,
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

Singleton {
    id: root
    property string display: "0"      // the expression being typed, or the last result
    readonly property string result: display      // what was last computed (or what is shown)
    property string preview: ""        // live "= …" while typing, "" when none
    property string error: ""          // last evaluation error, "" when the last one was fine
    property bool shown: false         // the panel is open (Modules/Calculator/Calculator.qml)
    property bool justEvaluated: false // after "=", a digit starts fresh instead of appending

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

    // 5! and (…)! as factorial calls, including nested parentheses.
    function rewriteFact(s) {
        const out = [];
        let i = 0;
        while (i < s.length) {
            const ch = s.charAt(i);
            if (ch === "(") {
                let depth = 0, j = i;
                for (; j < s.length; j++) {
                    if (s.charAt(j) === "(") depth++;
                    else if (s.charAt(j) === ")") { depth--; if (depth === 0) break; }
                }
                if (j < s.length && depth === 0 && s.charAt(j + 1) === "!") {
                    out.push("fact(" + s.slice(i + 1, j) + ")");
                    i = j + 2;
                    continue;
                }
            }
            const m = s.slice(i).match(/^(\d+(?:\.\d*)?)!/);
            if (m) { out.push("fact(" + m[1] + ")"); i += m[0].length; continue; }
            out.push(ch);
            i++;
        }
        return out.join("");
    }

    // the evaluator. Helpers fact/npr/ncr and the financial/programming
    // helpers below are computed with the local functions and passed into
    // the strict Function() wrapper; only a finite result survives (the
    // same rule as the launcher's calc()).
    function calc(expr) {
        let src = String(expr || "").replace(/\s+/g, "").replace(/\^/g, "**")
            .replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-")
            .replace(/√/g, "sqrt").replace(/π/g, "pi");
        src = src.replace(/\|([^|]+)\|/g, "abs($1)");            // |x| → abs(x)
        src = rewriteFact(src);                                 // 5! / (3+2)! → fact(…)
        if (!/^[0-9+\-*/%.()a-z,]+$/i.test(src) || !/[0-9]/.test(src) || /^[0-9.]+$/.test(src))
            return null;
        const names = src.match(/[a-z]+/gi) || [];
        const allowed = ["sqrt", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "exp", "abs", "round", "floor", "ceil", "pow", "min", "max", "fact", "npr", "ncr", "pi", "e", "fv", "pv", "rate", "sl", "ddb", "band", "bor", "bxor", "bnot", "lsh", "rsh"];
        if (names.some(n => allowed.indexOf(n.toLowerCase()) < 0))
            return null;
        // names are case-insensitive, JS is not (nPr → npr, PI → Math.PI)
        const js = src.replace(/\bln\(/gi, "log(").replace(/\bpi\b/gi, "PI").replace(/\be\b/g, "E")
            .replace(/\b(sqrt|sin|cos|tan|asin|acos|atan|log|exp|abs|round|floor|ceil|pow|min|max)\b/gi, m => "Math." + m.toLowerCase())
            .replace(/\bPI\b/g, "Math.PI").replace(/\bE\b/g, "Math.E")
            .replace(/\bnpr\b/gi, "npr").replace(/\bncr\b/gi, "ncr").replace(/\bfact\b/gi, "fact")
            .replace(/\b(fv|pv|rate|sl|ddb|band|bor|bxor|bnot|lsh|rsh)\b/gi, m => m.toLowerCase());
        try {
            const fact = function (n) {
                n = Math.floor(n);
                if (n < 0 || n > 170)
                    throw new Error("fact");
                let r = 1;
                for (let i = 2; i <= n; i++)
                    r *= i;
                return r;
            };
            const npr = function (n, k) { return fact(n) / fact(n - k); };              // nPr: n!/(n-k)!
            const ncr = function (n, k) { return fact(n) / (fact(k) * fact(n - k)); };  // nCr: n!/(k!(n-k)!)
            // financial (GNOME Calculator parity): through the same whitelist
            const fv = function (principal, rate, periods) { return principal * Math.pow(1 + rate, periods); }; // FV: P*(1+r)^n
            const pv = function (futureValue, rate, periods) { return futureValue / Math.pow(1 + rate, periods); }; // PV: FV/(1+r)^n
            const sl = function (cost, salvage, life) { // straight-line depreciation per period
                if (!isFinite(cost) || !isFinite(salvage) || !isFinite(life) || life <= 0)
                    throw new Error("sl");
                return (cost - salvage) / life;
            };
            const ddb = function (cost, salvage, life, period) { // double-declining-balance depreciation in `period`
                if (!isFinite(cost) || !isFinite(salvage) || !isFinite(life) || life <= 0 || !isFinite(period))
                    throw new Error("ddb");
                const n = Math.max(1, Math.floor(period));
                const baseAmt = cost - salvage;
                const d = 2 / life;
                return baseAmt * d * Math.pow(1 - d, n - 1);
            };
            const rate = function (principal, payment, periods) { // periodic interest rate: payment = P*r/(1-(1+r)^-n)
                if (!isFinite(principal) || !isFinite(payment) || !isFinite(periods) || principal <= 0 || payment <= 0 || periods <= 0)
                    throw new Error("rate");
                const n = periods;
                const pmtFor = function (r) {
                    if (Math.abs(r) < 1e-12)
                        return principal / n;
                    return principal * r / (1 - Math.pow(1 + r, -n));
                };
                // pmtFor is increasing on (-1, +inf): bracket and bisect
                let lo = -0.99, hi = 1;
                let fhi = pmtFor(hi) - payment;
                let guard = 0;
                while (fhi < 0 && guard++ < 60) {
                    hi = hi * 2 + 1;
                    fhi = pmtFor(hi) - payment;
                }
                for (let i = 0; i < 200; i++) {
                    const mid = (lo + hi) / 2;
                    const f = pmtFor(mid) - payment;
                    if (Math.abs(f) < 1e-12)
                        return mid;
                    if (f > 0)
                        hi = mid;
                    else
                        lo = mid;
                }
                return (lo + hi) / 2;
            };
            // programming (bitwise): 32-bit signed, like JS & | ^ ~ << >>
            const band = function (a, b) { return (Math.floor(a) | 0) & (Math.floor(b) | 0); };
            const bor = function (a, b) { return (Math.floor(a) | 0) | (Math.floor(b) | 0); };
            const bxor = function (a, b) { return (Math.floor(a) | 0) ^ (Math.floor(b) | 0); };
            const bnot = function (a) { return ~(Math.floor(a) | 0); };
            const lsh = function (a, n) { return (Math.floor(a) | 0) << (Math.floor(n) & 31); };
            const rsh = function (a, n) { return (Math.floor(a) | 0) >> (Math.floor(n) & 31); };
            const v = Function("fact", "npr", "ncr", "fv", "pv", "rate", "sl", "ddb", "band", "bor", "bxor", "bnot", "lsh", "rsh", '"use strict"; return (' + js + ");")(fact, npr, ncr, fv, pv, rate, sl, ddb, band, bor, bxor, bnot, lsh, rsh);
            return typeof v === "number" && isFinite(v) ? Number(v.toPrecision(12)) : null;
        } catch (e) {
            return null;
        }
    }

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

    // unit conversion: the table and temperature specials from
    // Modules/Launcher/Calc.js convert(), synced by hand because a Services
    // singleton cannot import a library from Modules. Returns { text, value }
    // or null when the units are unknown or of different dimensions.
    property var units: ({
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000], in: ["len", 0.0254], inch: ["len", 0.0254],
        ft: ["len", 0.3048], feet: ["len", 0.3048], foot: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344], miles: ["len", 1609.344],
        mg: ["mass", 1e-6], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.0283495], lb: ["mass", 0.453592], lbs: ["mass", 0.453592],
        ml: ["vol", 0.001], l: ["vol", 1], litre: ["vol", 1], liter: ["vol", 1], gal: ["vol", 3.78541], cup: ["vol", 0.24], tsp: ["vol", 0.00492892], tbsp: ["vol", 0.0147868],
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12], kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], day: ["time", 86400], days: ["time", 86400], week: ["time", 604800], weeks: ["time", 604800],
        kmh: ["speed", 1 / 3.6], "km/h": ["speed", 1 / 3.6], mph: ["speed", 0.44704], "m/s": ["speed", 1], knot: ["speed", 0.514444], knots: ["speed", 0.514444],
        m2: ["area", 1], km2: ["area", 1e6], ha: ["area", 1e4], acre: ["area", 4046.86], acres: ["area", 4046.86], sqft: ["area", 0.092903],
        c: ["temp"], f: ["temp"], k: ["temp"]
    })
    readonly property var unitNames: Object.keys(units).sort()

    function convertUnit(value, from, to) {
        const v = parseFloat(value), a = String(from || "").toLowerCase(), b = String(to || "").toLowerCase();
        const ua = units[a], ub = units[b];
        if (!ua || !ub || ua[0] !== ub[0] || isNaN(v))
            return null;
        let out;
        if (ua[0] === "temp") {
            const kel = a === "c" ? v + 273.15 : a === "f" ? (v - 32) * 5 / 9 + 273.15 : v;
            out = b === "c" ? kel - 273.15 : b === "f" ? (kel - 273.15) * 9 / 5 + 32 : kel;
        } else {
            out = v * ua[1] / ub[1];
        }
        if (!isFinite(out))
            return null;
        return { text: Number(out.toPrecision(8)) + " " + b, value: out };
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
