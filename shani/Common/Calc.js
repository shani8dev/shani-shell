// The shell's calculator and unit converter, for the launcher ("= 2*(3+4)^2",
// "5 km in miles") and the Calculator app (Services/Calculator) alike. One
// evaluator and one unit table: they were two hand-synced copies, and the
// launcher's had lost the financial and bitwise functions and the angle unit.
.pragma library
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
function calc(expr, angleUnit) {
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
    // log is base 10 and ln is natural, as on every calculator. Math.log
    // is the natural one, so after prefixing: log → log10, ln → Math.log.
    const js = src.replace(/\bpi\b/gi, "PI").replace(/\be\b/g, "E")
        .replace(/\b(sin|cos|tan|asin|acos|atan)\b/gi, m => "_" + m.toLowerCase())
        .replace(/\b(sqrt|log|ln|exp|abs|round|floor|ceil|pow|min|max)\b/gi, m => "Math." + m.toLowerCase())
        .replace(/Math\.log\(/g, "Math.log10(")
        .replace(/Math\.ln\(/g, "Math.log(")
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
        // trig through the angle unit (DEG default, RAD, GRAD): the wrappers
        // use the angle unit passed in (the Calculator's setting; radians when none).
        const toRad = function (x) {
            const u = String(angleUnit || "rad").toLowerCase();
            return u === "rad" ? x : u === "grad" ? x * Math.PI / 200 : x * Math.PI / 180;
        };
        const fromRad = function (x) {
            const u = String(angleUnit || "rad").toLowerCase();
            return u === "rad" ? x : u === "grad" ? x * 200 / Math.PI : x * 180 / Math.PI;
        };
        const _sin = function (x) { return Math.sin(toRad(x)); };
        const _cos = function (x) { return Math.cos(toRad(x)); };
        const _tan = function (x) { return Math.tan(toRad(x)); };
        const _asin = function (x) { return fromRad(Math.asin(x)); };
        const _acos = function (x) { return fromRad(Math.acos(x)); };
        const _atan = function (x) { return fromRad(Math.atan(x)); };
        const v = Function("fact", "npr", "ncr", "fv", "pv", "rate", "sl", "ddb", "band", "bor", "bxor", "bnot", "lsh", "rsh", "_sin", "_cos", "_tan", "_asin", "_acos", "_atan", '"use strict"; return (' + js + ");")(fact, npr, ncr, fv, pv, rate, sl, ddb, band, bor, bxor, bnot, lsh, rsh, _sin, _cos, _tan, _asin, _acos, _atan);
        return typeof v === "number" && isFinite(v) ? Number(v.toPrecision(12)) : null;
    } catch (e) {
        return null;
    }
}
var units = ({
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
function convert(q) {
    const m = q.trim().toLowerCase().match(/^(-?[\d.]+)\s*([a-z\/0-9°]+)\s+(?:in|to|as)\s+([a-z\/0-9°]+)$/);
    if (!m)
        return null;
    const v = parseFloat(m[1]), a = m[2].replace("°", ""), b = m[3].replace("°", "");
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
    return { text: Number(out.toPrecision(8)) + " " + m[3], value: out };
}
// three-letter codes followed by "in/to": currency, which needs live rates —
// Chronoa's convert_currency skill has them; the shell sends no query anywhere
// "convert 5 from km to mi" in the Calculator's Converter tab: { text, value } or null
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
function isCurrency(q) {
    return /^-?[\d.]+\s*[a-z]{3}\s+(in|to)\s+[a-z]{3}$/i.test(q.trim()) && convert(q) === null;
}
